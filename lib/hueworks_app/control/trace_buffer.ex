defmodule Hueworks.Control.TraceBuffer do
  @moduledoc false

  use GenServer

  @default_capacity 1_000
  @stages [
    :intent,
    :planned,
    :enqueued,
    :dispatch_started,
    :dispatch_finished,
    :convergence_retry,
    :converged,
    :failed
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def record(trace, stage, attrs \\ %{})

  def record(trace, stage, attrs)
      when is_map(trace) and stage in @stages and is_map(attrs) do
    maybe_cast({:record, trace, stage, attrs})
  end

  def record(_trace, _stage, _attrs), do: :ok

  def recent(filters \\ []) when is_list(filters) do
    maybe_call({:recent, filters}, empty_result())
  end

  def trace_summary(trace_id) when is_binary(trace_id) do
    maybe_call({:trace_summary, trace_id}, %{action_count: 0, bridge_count: 0})
  end

  def trace_summary(_trace_id), do: %{action_count: 0, bridge_count: 0}

  def clear do
    maybe_call(:clear, :ok)
  end

  @impl true
  def init(opts) do
    capacity = Keyword.get(opts, :capacity, @default_capacity)
    {:ok, %{queue: :queue.new(), next_sequence: 1, capacity: capacity}}
  end

  @impl true
  def handle_cast({:record, trace, stage, attrs}, state) do
    event = event(state.next_sequence, trace, stage, attrs)
    queue = :queue.in(event, state.queue)
    queue = trim(queue, state.capacity)

    {:noreply, %{state | queue: queue, next_sequence: state.next_sequence + 1}}
  end

  @impl true
  def handle_call({:recent, filters}, _from, state) do
    events =
      state.queue
      |> :queue.to_list()
      |> Enum.reverse()
      |> Enum.filter(&matches?(&1, filters))
      |> Enum.take(limit(filters))

    {:reply, %{capacity: state.capacity, retained_count: :queue.len(state.queue), events: events},
     state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | queue: :queue.new(), next_sequence: 1}}
  end

  def handle_call({:trace_summary, trace_id}, _from, state) do
    events =
      state.queue
      |> :queue.to_list()
      |> Enum.filter(&(&1.trace_id == trace_id))

    {:reply, summarize_trace(events), state}
  end

  defp event(sequence, trace, stage, attrs) do
    %{
      sequence: sequence,
      recorded_at: DateTime.utc_now(),
      trace_id: Map.get(trace, :trace_id),
      source: Map.get(trace, :source) || Map.get(trace, :trace_source),
      area_id: Map.get(trace, :area_id) || Map.get(trace, :trace_area_id),
      scene_id: Map.get(trace, :scene_id) || Map.get(trace, :trace_scene_id),
      stage: stage,
      entity_kind: Map.get(attrs, :entity_kind) || Map.get(attrs, :type),
      entity_id: Map.get(attrs, :entity_id) || Map.get(attrs, :id),
      bridge_id: Map.get(attrs, :bridge_id),
      desired: safe_state(Map.get(attrs, :desired)),
      planner_ms: Map.get(attrs, :planner_ms),
      action_count: Map.get(attrs, :action_count),
      bridge_count: Map.get(attrs, :bridge_count),
      queue_delay_ms: Map.get(attrs, :queue_delay_ms),
      dispatch_ms: Map.get(attrs, :dispatch_ms),
      total_elapsed_ms: Map.get(attrs, :total_elapsed_ms),
      result: result_category(Map.get(attrs, :result)),
      recovery_action_count: Map.get(attrs, :recovery_action_count),
      attempts: Map.get(attrs, :attempts)
    }
  end

  defp safe_state(state) when is_map(state) do
    state
    |> Map.take([:power, :brightness, :kelvin, :x, :y])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp safe_state(_state), do: nil

  defp result_category(:ok), do: :ok
  defp result_category({:error, _reason}), do: :error
  defp result_category(:error), do: :error
  defp result_category(nil), do: nil
  defp result_category(_result), do: :other

  defp trim(queue, capacity) do
    if :queue.len(queue) <= capacity do
      queue
    else
      {{:value, _event}, queue} = :queue.out(queue)
      trim(queue, capacity)
    end
  end

  defp matches?(event, filters) do
    Enum.all?(filters, fn
      {:limit, _value} ->
        true

      {key, value} when key in [:trace_id, :area_id, :entity_kind, :entity_id, :source] ->
        Map.get(event, key) == value

      _ ->
        false
    end)
  end

  defp limit(filters) do
    case Keyword.get(filters, :limit, 50) do
      value when is_integer(value) -> value |> max(1) |> min(100)
      _ -> 50
    end
  end

  defp summarize_trace(events) do
    case Enum.find(Enum.reverse(events), &operation_summary_event?/1) do
      %{action_count: action_count, bridge_count: bridge_count} ->
        %{action_count: action_count || 0, bridge_count: bridge_count || 0}

      nil ->
        plan_events = Enum.filter(events, &(&1.stage in [:planned, :enqueued]))

        %{
          action_count: plan_events |> Enum.map(&(&1.action_count || 0)) |> Enum.max(fn -> 0 end),
          bridge_count:
            plan_events
            |> Enum.map(& &1.bridge_id)
            |> Enum.reject(&is_nil/1)
            |> MapSet.new()
            |> MapSet.size()
        }
    end
  end

  defp operation_summary_event?(event) do
    event.stage == :enqueued and is_nil(event.entity_kind) and is_nil(event.entity_id)
  end

  defp empty_result, do: %{capacity: @default_capacity, retained_count: 0, events: []}

  defp maybe_cast(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      _ -> :ok
    end
  end

  defp maybe_call(message, default) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, message)
      _ -> default
    end
  end
end
