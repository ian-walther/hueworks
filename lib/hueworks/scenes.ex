defmodule Hueworks.Scenes do
  @moduledoc """
  Query helpers for scenes.
  """

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hueworks.Repo
  alias Hueworks.ActiveScenes
  alias Hueworks.DebugLogging
  alias Hueworks.Rooms
  alias Hueworks.Control.DesiredState
  alias Hueworks.Scenes.Intent
  alias Hueworks.Schemas.{LightState, Scene, SceneComponent, SceneComponentLight}

  def list_scenes_for_room(room_id) do
    Repo.all(from(s in Scene, where: s.room_id == ^room_id, order_by: [asc: s.name]))
  end

  def list_manual_light_states do
    Repo.all(
      from(ls in LightState,
        where: ls.type == :manual,
        order_by: [asc: ls.name, asc: ls.id]
      )
    )
  end

  def list_editable_light_states do
    Repo.all(
      from(ls in LightState,
        where: ls.type in [:manual, :circadian],
        order_by: [asc: ls.name, asc: ls.id]
      )
    )
  end

  def create_light_state(name, type, config \\ %{})

  def create_light_state(name, type, config)
      when type in [:manual, :circadian] do
    %LightState{}
    |> LightState.changeset(%{
      name: name,
      type: type,
      config: config || %{}
    })
    |> Repo.insert()
  end

  def create_light_state(_name, _type, _config), do: {:error, :invalid_type}

  def update_light_state(id, attrs) when is_integer(id) and is_map(attrs) do
    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: type} = state when type in [:manual, :circadian] ->
        config =
          Map.merge(
            state.config || %{},
            Map.get(attrs, :config) || Map.get(attrs, "config") || %{}
          )

        merged_attrs = Map.merge(%{name: state.name, type: state.type, config: config}, attrs)

        state
        |> LightState.changeset(merged_attrs)
        |> Repo.update()

      _ ->
        {:error, :invalid_type}
    end
  end

  def duplicate_light_state(id) when is_integer(id) do
    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: type} = state when type in [:manual, :circadian] ->
        %LightState{}
        |> LightState.changeset(%{
          name: "#{state.name} Copy",
          type: state.type,
          config: Map.new(state.config || %{})
        })
        |> Repo.insert()

      _ ->
        {:error, :invalid_type}
    end
  end

  def delete_light_state(id, opts \\ []) do
    _scene_id = Keyword.get(opts, :scene_id)

    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: type} = state when type in [:manual, :circadian] ->
        in_use =
          Repo.aggregate(
            from(sc in SceneComponent, where: sc.light_state_id == ^state.id),
            :count
          )

        cond do
          in_use == 0 ->
            Repo.delete(state)

          true ->
            {:error, :in_use}
        end

      _ ->
        {:error, :invalid_type}
    end
  end

  def create_manual_light_state(name, config \\ %{}),
    do: create_light_state(name, :manual, config)

  def update_manual_light_state(id, attrs), do: update_light_state(id, attrs)
  def duplicate_manual_light_state(id), do: duplicate_light_state(id)
  def delete_manual_light_state(id, opts \\ []), do: delete_light_state(id, opts)

  def create_scene(attrs) do
    %Scene{}
    |> Scene.changeset(attrs)
    |> Repo.insert()
  end

  def get_scene(id), do: Repo.get(Scene, id)

  def update_scene(scene, attrs) do
    scene
    |> Scene.changeset(attrs)
    |> Repo.update()
  end

  def delete_scene(scene) do
    Repo.delete(scene)
  end

  def refresh_active_scene(scene_id) when is_integer(scene_id) do
    case Repo.get(Scene, scene_id) do
      nil ->
        {:error, :not_found}

      %Scene{} = scene ->
        case ActiveScenes.get_for_room(scene.room_id) do
          %{scene_id: ^scene_id} = active_scene ->
            apply_active_scene(scene, active_scene)

          _ ->
            {:ok, %{}, %{}}
        end
    end
  end

  def refresh_active_scenes_for_light_state(light_state_id) when is_integer(light_state_id) do
    scene_ids =
      Repo.all(
        from(sc in SceneComponent,
          where: sc.light_state_id == ^light_state_id,
          distinct: true,
          select: sc.scene_id
        )
      )

    scenes_and_active =
      Repo.all(
        from(s in Scene,
          join: a in Hueworks.Schemas.ActiveScene,
          on: a.scene_id == s.id and a.room_id == s.room_id,
          where: s.id in ^scene_ids,
          select: {s, a}
        )
      )

    refreshed =
      Enum.reduce(scenes_and_active, [], fn {scene, active_scene}, acc ->
        case apply_active_scene(scene, active_scene) do
          {:ok, _diff, _updated} -> [scene | acc]
          _ -> acc
        end
      end)
      |> Enum.reverse()

    {:ok, refreshed}
  end

  def activate_scene(scene_id, opts \\ []) when is_integer(scene_id) do
    case Repo.get(Scene, scene_id) do
      nil ->
        {:error, :not_found}

      scene ->
        _ = ActiveScenes.set_active(scene)

        apply_scene(scene,
          brightness_override: false,
          force_apply: true,
          trace: Keyword.get(opts, :trace)
        )
    end
  end

  def apply_scene(%Scene{} = scene, opts \\ []) do
    scene =
      scene
      |> Repo.preload(scene_components: [:lights, :light_state, :scene_component_lights])

    brightness_override = Keyword.get(opts, :brightness_override, false)
    # TODO: replace this temporary fallback with HA-provided occupancy input.
    occupied = Keyword.get_lazy(opts, :occupied, fn -> Rooms.room_occupied?(scene.room_id) end)
    force_apply = Keyword.get(opts, :force_apply, false)
    trace = Keyword.get(opts, :trace)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    target_light_ids = opts |> Keyword.get(:target_light_ids, []) |> MapSet.new()
    circadian_only = Keyword.get(opts, :circadian_only, false)
    power_overrides = Keyword.get(opts, :power_overrides, %{})

    log_trace(
      trace,
      "apply_scene_start",
      room_id: scene.room_id,
      scene_id: scene.id,
      occupied: occupied,
      brightness_override: brightness_override,
      force_apply: force_apply
    )

    txn =
      Intent.build_transaction(scene,
        brightness_override: brightness_override,
        occupied: occupied,
        now: now,
        target_light_ids: target_light_ids,
        circadian_only: circadian_only,
        power_overrides: power_overrides
      )

    result = DesiredState.commit(txn)

    case result do
      {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: updated}} ->
        plan_diff =
          if force_apply do
            txn.changes
          else
            merge_plan_diff(intent_diff, reconcile_diff)
          end

        log_trace(trace, "apply_scene_diff", diff_size: map_size(plan_diff))

        if map_size(plan_diff) > 0 do
          planner_started_ms = monotonic_ms()
          plan = Hueworks.Control.Planner.plan_room(scene.room_id, plan_diff, trace: trace)
          planner_ms = monotonic_ms() - planner_started_ms

          log_trace(
            trace,
            "plan_built",
            planner_ms: planner_ms,
            actions_total: length(plan),
            group_actions: count_action_type(plan, :group),
            light_actions: count_action_type(plan, :light),
            off_actions: count_power(plan, :off),
            on_actions: count_power(plan, :on)
          )

          enqueued_at_ms = monotonic_ms()
          traced_plan = attach_trace(plan, trace, scene, occupied, enqueued_at_ms)
          _ = Hueworks.Control.Executor.enqueue(traced_plan)
          log_trace(trace, "plan_enqueued", actions_total: length(traced_plan))
        end

        {:ok, plan_diff, updated}

      _ ->
        result
    end
  end

  def reapply_active_scene_lights(room_id, light_ids, opts \\ [])

  def reapply_active_scene_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    light_ids =
      light_ids
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    case {light_ids, ActiveScenes.get_for_room(room_id)} do
      {[], _active_scene} ->
        {:ok, %{}, %{}}

      {_light_ids, nil} ->
        {:ok, %{}, %{}}

      {_light_ids, active_scene} ->
        case get_scene(active_scene.scene_id) do
          nil ->
            {:error, :not_found}

          scene ->
            power_overrides =
              case Keyword.get(opts, :power_override) do
                nil -> %{}
                power -> Map.new(light_ids, &{&1, power})
              end

            apply_scene(scene,
              brightness_override: false,
              occupied: Rooms.room_occupied?(room_id),
              target_light_ids: light_ids,
              circadian_only: Keyword.get(opts, :circadian_only, false),
              power_overrides: power_overrides,
              now: Keyword.get(opts, :now, DateTime.utc_now()),
              trace: Keyword.get(opts, :trace)
            )
        end
    end
  end

  def reapply_active_scene_lights(_room_id, _light_ids, _opts), do: {:error, :invalid_args}

  def reapply_active_circadian_lights(room_id, light_ids, opts \\ [])

  def reapply_active_circadian_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    reapply_active_scene_lights(room_id, light_ids, Keyword.put(opts, :circadian_only, true))
  end

  def reapply_active_circadian_lights(_room_id, _light_ids, _opts), do: {:error, :invalid_args}

  def replace_scene_components(%Scene{} = scene, components) when is_list(components) do
    Repo.transaction(fn ->
      Repo.delete_all(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

      Enum.reduce_while(components, :ok, fn component, _acc ->
        case resolve_component_light_state(component) do
          {:error, reason} ->
            Repo.rollback(reason)

          {:ok, light_state} ->
            scene_component =
              %SceneComponent{}
              |> SceneComponent.changeset(%{
                name: Map.get(component, :name),
                scene_id: scene.id,
                light_state_id: light_state.id,
                metadata: %{}
              })
              |> Repo.insert!()

            light_ids = Map.get(component, :light_ids, [])

            Enum.each(light_ids, fn light_id ->
              %SceneComponentLight{}
              |> SceneComponentLight.changeset(%{
                scene_component_id: scene_component.id,
                light_id: light_id,
                default_power: Intent.default_power_for_light(component, light_id)
              })
              |> Repo.insert!()
            end)

            {:cont, :ok}
        end
      end)
    end)
  end

  defp resolve_component_light_state(component) do
    state_id = Map.get(component, :light_state_id)

    cond do
      state_id in [nil, "new", "new_manual", "new_circadian"] ->
        {:error, :invalid_light_state}

      true ->
        state_id
        |> parse_id()
        |> case do
          nil ->
            {:error, :invalid_light_state}

          id ->
            case Repo.get(LightState, id) do
              %LightState{} = state when state.type in [:manual, :circadian] ->
                {:ok, state}

              _ ->
                {:error, :invalid_light_state}
            end
        end
    end
  end

  defp apply_active_scene(%Scene{} = scene, active_scene) do
    case apply_scene(scene,
           brightness_override: Map.get(active_scene, :brightness_override, false),
           occupied: Rooms.room_occupied?(scene.room_id)
         ) do
      {:ok, _diff, _updated} = ok ->
        _ = ActiveScenes.mark_applied(active_scene)
        ok

      other ->
        other
    end
  end

  defp parse_id(value), do: Hueworks.Util.parse_id(value)

  defp attach_trace(plan, nil, _scene, _occupied, _enqueued_at_ms), do: plan

  defp attach_trace(plan, trace, scene, occupied, enqueued_at_ms)
       when is_list(plan) and is_map(trace) do
    trace_id = Map.get(trace, :trace_id) || Map.get(trace, "trace_id")
    source = Map.get(trace, :source) || Map.get(trace, "source")
    started_at_ms = Map.get(trace, :started_at_ms) || Map.get(trace, "started_at_ms")

    Enum.map(plan, fn action ->
      action
      |> Map.put(:trace_id, trace_id)
      |> Map.put(:trace_source, source)
      |> Map.put(:trace_room_id, scene.room_id)
      |> Map.put(:trace_scene_id, scene.id)
      |> Map.put(:trace_target_occupied, occupied)
      |> Map.put(:trace_started_at_ms, started_at_ms)
      |> Map.put(:enqueued_at_ms, enqueued_at_ms)
    end)
  end

  defp attach_trace(plan, _trace, _scene, _occupied, _enqueued_at_ms), do: plan

  defp count_action_type(actions, type) do
    Enum.count(actions, &(&1.type == type))
  end

  defp count_power(actions, power) do
    Enum.count(actions, fn action ->
      desired = Map.get(action, :desired) || %{}
      (Map.get(desired, :power) || Map.get(desired, "power")) == power
    end)
  end

  defp merge_plan_diff(left, right) when left == %{}, do: right
  defp merge_plan_diff(left, right) when right == %{}, do: left

  defp merge_plan_diff(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_attrs, right_attrs ->
      Map.merge(left_attrs, right_attrs)
    end)
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp log_trace(nil, _event, _kv), do: :ok

  defp log_trace(trace, event, kv) when is_map(trace) and is_list(kv) do
    trace_id = Map.get(trace, :trace_id) || Map.get(trace, "trace_id")
    source = Map.get(trace, :source) || Map.get(trace, "source")

    attrs =
      kv
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

    DebugLogging.info("[occ-trace #{trace_id}] #{event} source=#{source} #{attrs}")
  end
end
