defmodule Hueworks.Scenes.Apply do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.Apply, as: ControlApply
  alias Hueworks.DebugLogging
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Scenes.Components
  alias Hueworks.Scenes.Intent
  alias Hueworks.Scenes.Intent.BuildOptions
  alias Hueworks.Schemas.Scene

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
      |> attach_effective_light_states()

    occupied = Keyword.get_lazy(opts, :occupied, fn -> Rooms.room_occupied?(scene.room_id) end)

    intent_opts =
      opts
      |> Keyword.put(:occupied, occupied)
      |> BuildOptions.from_opts()

    preserve_power_latches = intent_opts.preserve_power_latches
    force_apply = Keyword.get(opts, :force_apply, false)
    enqueue_mode = Keyword.get(opts, :enqueue_mode, :replace)

    trace =
      opts
      |> Keyword.get(:trace)
      |> ensure_trace(scene, occupied)
      |> enrich_trace(scene, occupied)

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
    power_overrides =
      active_scene
      |> ActiveScenes.power_overrides()
      |> Map.merge(Keyword.get(opts, :power_overrides, %{}))

    apply_opts =
      opts
      |> Keyword.put(:power_overrides, power_overrides)
      |> Keyword.put_new(:enqueue_mode, :replace_targets)

    case apply_scene(scene, apply_opts) do
      {:ok, _diff, _updated} = ok ->
        _ = ActiveScenes.mark_applied(active_scene)
        ok

      other ->
        other
    end
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

  defp ensure_trace(nil, scene, occupied) do
    %{
      trace_id: "scene-#{scene.id}-#{System.unique_integer([:positive])}",
      source: "scenes.apply_scene",
      started_at_ms: System.monotonic_time(:millisecond),
      trace_room_id: scene.room_id,
      trace_scene_id: scene.id,
      trace_target_occupied: occupied
    }
  end

  defp ensure_trace(trace, _scene, _occupied), do: trace

  defp attach_effective_light_states(%Scene{} = scene) do
    scene_components =
      Enum.map(scene.scene_components, fn component ->
        Map.put(component, :light_state, Components.effective_light_state(component))
      end)

    %{scene | scene_components: scene_components}
  end
end
