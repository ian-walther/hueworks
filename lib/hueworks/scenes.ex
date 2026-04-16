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
  alias Hueworks.Control.Apply, as: ControlApply
  alias Hueworks.Scenes.Active
  alias Hueworks.Scenes.Components
  alias Hueworks.Scenes.Intent
  alias Hueworks.Scenes.Intent.BuildOptions
  alias Hueworks.Scenes.LightStates
  alias Hueworks.Scenes.Persistence
  alias Hueworks.Schemas.Scene

  def list_scenes_for_room(room_id) do
    Repo.all(from(s in Scene, where: s.room_id == ^room_id, order_by: [asc: s.name]))
  end

  def list_manual_light_states do
    LightStates.list_manual()
  end

  def list_editable_light_states do
    LightStates.list_editable()
  end

  def list_editable_light_states_with_usage do
    LightStates.list_editable_with_usage()
  end

  def get_editable_light_state(id) when is_integer(id) do
    LightStates.get_editable(id)
  end

  def get_editable_light_state(_id), do: nil

  def light_state_usages(id) when is_integer(id) do
    LightStates.usages(id)
  end

  def light_state_usages(_id), do: []

  def create_light_state(name, type, config \\ %{})

  def create_light_state(name, type, config)
      when type in [:manual, :circadian] do
    LightStates.create(name, type, config)
  end

  def create_light_state(_name, _type, _config), do: {:error, :invalid_type}

  def update_light_state(id, attrs) when is_integer(id) and is_map(attrs) do
    LightStates.update(id, attrs)
  end

  def duplicate_light_state(id) when is_integer(id) do
    LightStates.duplicate(id)
  end

  def delete_light_state(id, opts \\ []) do
    _scene_id = Keyword.get(opts, :scene_id)

    LightStates.delete(id)
  end

  def create_manual_light_state(name, config \\ %{}),
    do: create_light_state(name, :manual, config)

  def update_manual_light_state(id, attrs), do: update_light_state(id, attrs)
  def duplicate_manual_light_state(id), do: duplicate_light_state(id)
  def delete_manual_light_state(id, opts \\ []), do: delete_light_state(id, opts)

  def create_scene(attrs) do
    Persistence.create(attrs)
  end

  def get_scene(id), do: Repo.get(Scene, id)

  def update_scene(scene, attrs) do
    Persistence.update(scene, attrs)
  end

  def delete_scene(scene) do
    Persistence.delete(scene)
  end

  def refresh_active_scene(scene_id) when is_integer(scene_id) do
    Active.refresh_scene(scene_id)
  end

  def refresh_active_scenes_for_light_state(light_state_id) when is_integer(light_state_id) do
    Active.refresh_for_light_state(light_state_id)
  end

  def activate_scene(scene_id, opts \\ []) when is_integer(scene_id) do
    case Repo.get(Scene, scene_id) do
      nil ->
        {:error, :not_found}

      scene ->
        _ = ActiveScenes.set_active(scene)

        scene
        |> apply_scene(
          opts
          |> Keyword.put(:preserve_power_latches, false)
          |> Keyword.put(:force_apply, true)
          |> Keyword.put_new(:enqueue_mode, :append)
        )
    end
  end

  def apply_scene(%Scene{} = scene, opts \\ []) do
    scene =
      scene
      |> Repo.preload(scene_components: [:lights, :light_state, :scene_component_lights])

    occupied = Keyword.get_lazy(opts, :occupied, fn -> Rooms.room_occupied?(scene.room_id) end)

    intent_opts =
      opts
      |> Keyword.put(:occupied, occupied)
      |> BuildOptions.from_opts()

    preserve_power_latches = intent_opts.preserve_power_latches
    force_apply = Keyword.get(opts, :force_apply, false)
    enqueue_mode = Keyword.get(opts, :enqueue_mode, :replace)
    trace = enrich_trace(Keyword.get(opts, :trace), scene, occupied)

    log_trace(
      trace,
      "apply_scene_start",
      room_id: scene.room_id,
      scene_id: scene.id,
      occupied: occupied,
      preserve_power_latches: preserve_power_latches,
      force_apply: force_apply
    )

    txn = Intent.build_transaction(scene, intent_opts)

    result =
      ControlApply.commit_and_enqueue(txn, scene.room_id,
        force_apply: force_apply,
        enqueue_mode: enqueue_mode,
        trace: trace
      )

    case result do
      {:ok, %{plan_diff: plan_diff, updated: updated}} ->
        log_trace(trace, "apply_scene_diff", diff_size: map_size(plan_diff))

        {:ok, plan_diff, updated}

      _ ->
        result
    end
  end

  def apply_active_scene(%Scene{} = scene, active_scene, opts \\ []) when is_list(opts) do
    case apply_scene(scene, opts) do
      {:ok, _diff, _updated} = ok ->
        _ = ActiveScenes.mark_applied(active_scene)
        ok

      other ->
        other
    end
  end

  def recompute_active_scene_lights(room_id, light_ids, opts \\ [])

  def recompute_active_scene_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    Active.recompute_lights(room_id, light_ids, opts)
  end

  def recompute_active_scene_lights(_room_id, _light_ids, _opts), do: {:error, :invalid_args}

  def recompute_active_circadian_lights(room_id, light_ids, opts \\ [])

  def recompute_active_circadian_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    Active.recompute_circadian_lights(room_id, light_ids, opts)
  end

  def recompute_active_circadian_lights(_room_id, _light_ids, _opts),
    do: {:error, :invalid_args}

  # Temporary compatibility wrappers while callers migrate to the clearer
  # "recompute" naming.
  def reapply_active_scene_lights(room_id, light_ids, opts \\ []) do
    recompute_active_scene_lights(room_id, light_ids, opts)
  end

  def reapply_active_circadian_lights(room_id, light_ids, opts \\ []) do
    recompute_active_circadian_lights(room_id, light_ids, opts)
  end

  def replace_scene_components(%Scene{} = scene, components) when is_list(components) do
    Components.replace(scene, components)
  end

  defp log_trace(nil, _event, _kv), do: :ok

  defp log_trace(trace, event, kv) when is_map(trace) and is_list(kv) do
    trace_id = Map.get(trace, :trace_id) || Map.get(trace, "trace_id")
    source = Map.get(trace, :source) || Map.get(trace, "source")

    attrs =
      kv
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

    DebugLogging.info("[occ-trace #{trace_id}] #{event} source=#{source} #{attrs}")
  end

  defp enrich_trace(nil, _scene, _occupied), do: nil

  defp enrich_trace(trace, scene, occupied) when is_map(trace) do
    trace
    |> Map.put_new(:trace_room_id, scene.room_id)
    |> Map.put_new(:trace_scene_id, scene.id)
    |> Map.put_new(:trace_target_occupied, occupied)
  end
end
