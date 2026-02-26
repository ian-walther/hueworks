defmodule Hueworks.Scenes do
  @moduledoc """
  Query helpers for scenes.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState
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

  def activate_scene(scene_id) when is_integer(scene_id) do
    case Repo.get(Scene, scene_id) do
      nil ->
        {:error, :not_found}

      scene ->
        _ = ActiveScenes.set_active(scene)
        apply_scene(scene, brightness_override: false, force_apply: true)
    end
  end

  def apply_scene(%Scene{} = scene, opts \\ []) do
    scene =
      scene
      |> Repo.preload(scene_components: [:lights, :light_state, :scene_component_lights])

    brightness_override = Keyword.get(opts, :brightness_override, false)
    # TODO: replace this temporary fallback with HA-provided occupancy input.
    occupied = Keyword.get(opts, :occupied, true)
    force_apply = Keyword.get(opts, :force_apply, false)

    txn = DesiredState.begin(scene.id)

    txn =
      Enum.reduce(scene.scene_components, txn, fn component, txn ->
        desired = desired_from_light_state(component.light_state, brightness_override)
        default_power_by_light = component_default_power_map(component)

        Enum.reduce(component.lights, txn, fn light, txn ->
          light_desired =
            maybe_apply_default_power(
              desired,
              component.light_state,
              Map.get(default_power_by_light, light.id, :force_on),
              occupied
            )

          DesiredState.apply(txn, :light, light.id, light_desired)
        end)
      end)

    result = DesiredState.commit(txn)

    case result do
      {:ok, diff, _updated} ->
        plan_diff = if force_apply, do: txn.changes, else: diff

        if map_size(plan_diff) > 0 do
          plan = Hueworks.Control.Planner.plan_room(scene.room_id, plan_diff)
          _ = Hueworks.Control.Executor.enqueue(plan)
        end

        result

      _ ->
        result
    end
  end

  defp desired_from_light_state(%LightState{type: :manual, config: config}, brightness_override) do
    base = %{power: :on}

    base =
      if brightness_override do
        base
      else
        maybe_put(base, :brightness, config, ["brightness"])
      end

    base
    |> maybe_put(:kelvin, config, ["temperature", "kelvin"])
  end

  defp desired_from_light_state(_, _brightness_override), do: %{}

  defp maybe_apply_default_power(desired, %LightState{type: type}, power_policy, occupied)
       when type in [:manual, :circadian] do
    Map.put(desired, :power, resolve_power_policy(power_policy, occupied))
  end

  defp maybe_apply_default_power(desired, _light_state, _power_policy, _occupied), do: desired

  defp resolve_power_policy(:force_on, _occupied), do: :on
  defp resolve_power_policy("force_on", _occupied), do: :on
  defp resolve_power_policy(:force_off, _occupied), do: :off
  defp resolve_power_policy("force_off", _occupied), do: :off
  defp resolve_power_policy(:follow_occupancy, true), do: :on
  defp resolve_power_policy("follow_occupancy", true), do: :on
  defp resolve_power_policy(:follow_occupancy, false), do: :off
  defp resolve_power_policy("follow_occupancy", false), do: :off
  defp resolve_power_policy(_unknown, _occupied), do: :on

  defp component_default_power_map(component) do
    component
    |> Map.get(:scene_component_lights, [])
    |> Enum.reduce(%{}, fn join, acc ->
      Map.put(acc, join.light_id, parse_default_power(join.default_power))
    end)
  end

  defp maybe_put(attrs, key, config, keys) do
    value =
      Enum.find_value(keys, fn config_key ->
        Map.get(config, config_key) ||
          Map.get(config, map_key_atom(config_key))
      end)

    if is_nil(value) do
      attrs
    else
      Map.put(attrs, key, value)
    end
  end

  defp map_key_atom("brightness"), do: :brightness
  defp map_key_atom("temperature"), do: :temperature
  defp map_key_atom("kelvin"), do: :kelvin
  defp map_key_atom(_), do: nil

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
                default_power: component_light_default_power(component, light_id)
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

  defp component_light_default_power(component, light_id) do
    defaults =
      Map.get(component, :light_defaults) ||
        Map.get(component, "light_defaults") ||
        %{}

    defaults
    |> light_default_lookup(light_id)
    |> parse_default_power()
  end

  defp light_default_lookup(defaults, light_id) when is_map(defaults) do
    cond do
      Map.has_key?(defaults, light_id) ->
        Map.get(defaults, light_id)

      Map.has_key?(defaults, to_string(light_id)) ->
        Map.get(defaults, to_string(light_id))

      true ->
        nil
    end
  end

  defp light_default_lookup(_defaults, _light_id), do: nil

  defp parse_default_power(value) when value in [nil, true, "true", 1, "1", :on, "on"],
    do: :force_on

  defp parse_default_power(value) when value in [false, "false", 0, "0", :off, "off"],
    do: :force_off

  defp parse_default_power(value) when value in [:force_on, "force_on"], do: :force_on
  defp parse_default_power(value) when value in [:force_off, "force_off"], do: :force_off

  defp parse_default_power(value) when value in [:follow_occupancy, "follow_occupancy"],
    do: :follow_occupancy

  defp parse_default_power(_value), do: :force_on

  defp parse_id(value), do: Hueworks.Util.parse_id(value)
end
