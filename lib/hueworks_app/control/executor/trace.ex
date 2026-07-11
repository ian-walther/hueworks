defmodule Hueworks.Control.Executor.Trace do
  @moduledoc false

  alias Hueworks.Control.TraceBuffer
  alias Hueworks.DebugLogging

  def log_dispatch_start(action, dispatch_started_ms, queue_len_after_pop) do
    case Map.get(action, :trace_id) do
      nil ->
        :ok

      trace_id ->
        queue_delay_ms = queue_delay_ms(action, dispatch_started_ms)

        TraceBuffer.record(action_trace(action), :dispatch_started, %{
          type: action.type,
          id: action.id,
          bridge_id: action.bridge_id,
          desired: action.desired,
          queue_delay_ms: queue_delay_ms
        })

        DebugLogging.info(
          "[control-trace #{trace_id}] dispatch_start type=#{action.type} id=#{action.id} bridge_id=#{action.bridge_id} queue_delay_ms=#{queue_delay_ms} queue_len_after_pop=#{queue_len_after_pop} desired=#{inspect(action.desired)}"
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

        trace = action_trace(action)

        TraceBuffer.record(trace, :dispatch_finished, %{
          type: action.type,
          id: action.id,
          bridge_id: action.bridge_id,
          desired: action.desired,
          dispatch_ms: dispatch_ms,
          total_elapsed_ms: total_elapsed_ms,
          result: result
        })

        if match?({:error, _}, result) do
          TraceBuffer.record(trace, :failed, %{
            type: action.type,
            id: action.id,
            bridge_id: action.bridge_id,
            desired: action.desired,
            result: result,
            attempts: action.attempts
          })
        end

        DebugLogging.info(
          "[control-trace #{trace_id}] dispatch_end type=#{action.type} id=#{action.id} result=#{inspect(result)} dispatch_ms=#{dispatch_ms} total_elapsed_ms=#{total_elapsed_ms}"
        )
    end
  end

  def log_convergence_ok(action) do
    case Map.get(action, :trace_id) do
      nil ->
        :ok

      trace_id ->
        TraceBuffer.record(action_trace(action), :converged, %{
          type: action.type,
          id: action.id,
          bridge_id: action.bridge_id,
          desired: action.desired,
          attempts: action.attempts
        })

        DebugLogging.info(
          "[control-trace #{trace_id}] convergence_ok type=#{action.type} id=#{action.id} attempts=#{action.attempts}"
        )
    end
  end

  def log_convergence_retry(action, recovery_actions) do
    case Map.get(action, :trace_id) do
      nil ->
        :ok

      trace_id ->
        TraceBuffer.record(action_trace(action), :convergence_retry, %{
          type: action.type,
          id: action.id,
          bridge_id: action.bridge_id,
          desired: action.desired,
          attempts: action.attempts,
          recovery_action_count: length(recovery_actions)
        })

        DebugLogging.info(
          "[control-trace #{trace_id}] convergence_retry type=#{action.type} id=#{action.id} attempts=#{action.attempts} recovery_actions=#{length(recovery_actions)}"
        )
    end
  end

  def action_trace(action) do
    %{}
    |> maybe_put_trace(:trace_id, Map.get(action, :trace_id))
    |> maybe_put_trace(:source, Map.get(action, :trace_source))
    |> maybe_put_trace(:room_id, Map.get(action, :trace_room_id))
    |> maybe_put_trace(:scene_id, Map.get(action, :trace_scene_id))
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
