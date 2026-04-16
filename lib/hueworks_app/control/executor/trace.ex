defmodule Hueworks.Control.Executor.Trace do
  @moduledoc false

  alias Hueworks.DebugLogging

  def log_dispatch_start(action, dispatch_started_ms, queue_len_after_pop) do
    case Map.get(action, :trace_id) do
      nil ->
        :ok

      trace_id ->
        queue_delay_ms = queue_delay_ms(action, dispatch_started_ms)

        DebugLogging.info(
          "[occ-trace #{trace_id}] dispatch_start type=#{action.type} id=#{action.id} bridge_id=#{action.bridge_id} queue_delay_ms=#{queue_delay_ms} queue_len_after_pop=#{queue_len_after_pop} desired=#{inspect(action.desired)}"
        )
    end
  end

  def log_dispatch_end(action, result, dispatch_started_ms, dispatch_completed_ms) do
    case Map.get(action, :trace_id) do
      nil ->
        :ok

      trace_id ->
        dispatch_ms = dispatch_completed_ms - dispatch_started_ms
        total_elapsed_ms = total_elapsed_ms(action, dispatch_completed_ms)

        DebugLogging.info(
          "[occ-trace #{trace_id}] dispatch_end type=#{action.type} id=#{action.id} result=#{inspect(result)} dispatch_ms=#{dispatch_ms} total_elapsed_ms=#{total_elapsed_ms}"
        )
    end
  end

  def log_convergence_ok(action) do
    case Map.get(action, :trace_id) do
      nil ->
        :ok

      trace_id ->
        DebugLogging.info(
          "[occ-trace #{trace_id}] convergence_ok type=#{action.type} id=#{action.id} attempts=#{action.attempts}"
        )
    end
  end

  def log_convergence_retry(action, recovery_actions) do
    case Map.get(action, :trace_id) do
      nil ->
        :ok

      trace_id ->
        DebugLogging.info(
          "[occ-trace #{trace_id}] convergence_retry type=#{action.type} id=#{action.id} attempts=#{action.attempts} recovery_actions=#{length(recovery_actions)}"
        )
    end
  end

  def action_trace(action) do
    %{}
    |> maybe_put_trace(:trace_id, Map.get(action, :trace_id))
    |> maybe_put_trace(:source, Map.get(action, :trace_source))
  end

  def copy_trace_metadata(recovery_action, action) do
    trace_keys = [
      :trace_id,
      :trace_source,
      :trace_room_id,
      :trace_scene_id,
      :trace_target_occupied,
      :trace_started_at_ms
    ]

    Enum.reduce(trace_keys, recovery_action, fn key, acc ->
      case Map.fetch(action, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp queue_delay_ms(action, dispatch_started_ms) do
    case Map.get(action, :enqueued_at_ms) do
      value when is_integer(value) -> dispatch_started_ms - value
      _ -> 0
    end
  end

  defp total_elapsed_ms(action, dispatch_completed_ms) do
    case Map.get(action, :trace_started_at_ms) do
      value when is_integer(value) -> dispatch_completed_ms - value
      _ -> nil
    end
  end

  defp maybe_put_trace(trace, _key, nil), do: trace
  defp maybe_put_trace(trace, key, value), do: Map.put(trace, key, value)
end
