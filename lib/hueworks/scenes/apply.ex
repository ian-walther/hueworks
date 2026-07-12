defmodule Hueworks.Scenes.Apply do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.{Apply, Operation, TransitionPolicy}
  alias Hueworks.DebugLogging
  alias Hueworks.Repo
  alias Hueworks.Scenes.Components
  alias Hueworks.Scenes.Intent
  alias Hueworks.Scenes.Intent.BuildOptions
  alias Hueworks.Schemas.Scene

  def activate_scene(scene_or_id, opts \\ [])

  def activate_scene(scene_id, opts) when is_integer(scene_id) do
    case Repo.get(Scene, scene_id) do
      nil ->
        {:error, :not_found}

      scene ->
        activate_scene(scene, opts)
    end
  end

  def activate_scene(%Scene{} = scene, opts) when is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    operation = Operation.scene_activation(scene, opts)

    with {:ok, _active_scene} <-
           ActiveScenes.set_active(scene,
             now: now,
             circadian_resume_at: circadian_resume_at(operation.transition_policy, now)
           ) do
      scene
      |> apply_scene(
        opts
        |> Keyword.put(:operation, operation)
        |> Keyword.put(:preserve_power_latches, false)
        |> Keyword.put(:force_apply, true)
        |> Keyword.put_new(:enqueue_mode, :replace_targets)
      )
    end
  end

  def apply_scene(%Scene{} = scene, opts \\ []) do
    scene =
      scene
      |> Repo.preload(
        [
          scene_components: [
            :lights,
            :light_state,
            scene_component_lights: :presence_input
          ]
        ],
        force: true
      )
      |> attach_effective_light_states()

    intent_opts =
      opts
      |> BuildOptions.from_opts()

    preserve_power_latches = intent_opts.preserve_power_latches
    force_apply = Keyword.get(opts, :force_apply, false)
    enqueue_mode = Keyword.get(opts, :enqueue_mode, :replace_targets)

    trace =
      opts
      |> Keyword.get(:trace)
      |> ensure_trace(scene)
      |> enrich_trace(scene)

    operation =
      opts
      |> Keyword.get(:operation)
      |> case do
        %Operation{} = operation ->
          %{operation | trace: trace}

        _ ->
          Operation.new(
            origin: Keyword.get(opts, :origin, :scene_refresh),
            transition_policy: Keyword.get(opts, :transition_policy),
            trace: trace
          )
      end

    log_trace(
      trace,
      "apply_scene_start",
      room_id: scene.room_id,
      scene_id: scene.id,
      preserve_power_latches: preserve_power_latches,
      force_apply: force_apply
    )

    txn = Intent.build_transaction(scene, intent_opts)

    result =
      Apply.commit_and_enqueue(txn, scene.room_id,
        force_apply: force_apply,
        enqueue_mode: enqueue_mode,
        operation: operation,
        group_candidate_light_ids: Keyword.get(opts, :group_candidate_light_ids)
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

  defp log_trace(trace, event, kv) when is_map(trace) and is_list(kv) do
    trace_id = Map.get(trace, :trace_id) || Map.get(trace, "trace_id")
    source = Map.get(trace, :source) || Map.get(trace, "source")

    attrs =
      kv
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

    DebugLogging.info("[scene-trace #{trace_id}] #{event} source=#{source} #{attrs}")
  end

  defp log_trace(_trace, _event, _kv), do: :ok

  defp enrich_trace(trace, scene) when is_map(trace) do
    trace
    |> Map.put_new(:trace_room_id, scene.room_id)
    |> Map.put_new(:trace_scene_id, scene.id)
  end

  defp enrich_trace(trace, _scene), do: trace

  defp ensure_trace(nil, scene) do
    %{
      trace_id: "scene-#{scene.id}-#{System.unique_integer([:positive])}",
      source: "scenes.apply_scene",
      started_at_ms: System.monotonic_time(:millisecond),
      trace_room_id: scene.room_id,
      trace_scene_id: scene.id
    }
  end

  defp ensure_trace(trace, _scene), do: trace

  defp attach_effective_light_states(%Scene{} = scene) do
    scene_components =
      Enum.map(scene.scene_components, fn component ->
        Map.put(component, :light_state, Components.effective_light_state(component))
      end)

    %{scene | scene_components: scene_components}
  end

  defp circadian_resume_at(%TransitionPolicy{duration_ms: duration_ms}, now)
       when is_integer(duration_ms) and duration_ms > 0 do
    DateTime.add(now, duration_ms, :millisecond)
  end

  defp circadian_resume_at(_policy, _now), do: nil
end
