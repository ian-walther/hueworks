defmodule Hueworks.Control.Apply do
  @moduledoc false

  alias Hueworks.DebugLogging
  alias Hueworks.Control.{DesiredState, Executor, Operation, Planner, TraceBuffer}

  @type plan_diff :: map()
  @type commit_result :: %{
          plan_diff: plan_diff(),
          intent_diff: map(),
          reconcile_diff: map(),
          updated: map()
        }
  @type planner_result :: %{
          plan: list(map()),
          planner_ms: non_neg_integer()
        }

  @spec commit_transaction(DesiredState.transaction(), keyword()) ::
          {:ok, commit_result()}
  def commit_transaction(%DesiredState.Transaction{} = txn, opts \\ []) do
    force_apply = Keyword.get(opts, :force_apply, false)

    {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: updated}} =
      DesiredState.commit(txn)

    plan_diff =
      if force_apply do
        txn.changes
      else
        merge_plan_diff(intent_diff, reconcile_diff)
      end

    {:ok,
     %{
       plan_diff: plan_diff,
       intent_diff: intent_diff,
       reconcile_diff: reconcile_diff,
       updated: updated
     }}
  end

  @spec commit_and_enqueue(DesiredState.transaction(), integer(), keyword()) ::
          {:ok, map()} | {:error, {:invalid_room_id, integer()}}
  def commit_and_enqueue(%DesiredState.Transaction{} = txn, room_id, opts \\ []) do
    opts = ensure_operation(opts)
    force_apply = Keyword.get(opts, :force_apply, false)
    {:ok, %{plan_diff: plan_diff} = result} = commit_transaction(txn, force_apply: force_apply)
    record_intent(operation_trace(opts), plan_diff)

    case plan_and_enqueue(room_id, plan_diff, opts) do
      {:ok, %{plan: plan, planner_ms: planner_ms}} ->
        {:ok, result |> Map.put(:plan, plan) |> Map.put(:planner_ms, planner_ms)}

      other ->
        other
    end
  end

  def build_plan(room_id, diff, opts \\ [])
  def build_plan(_room_id, diff, _opts) when map_size(diff) == 0, do: []

  @spec build_plan(integer(), map(), keyword()) :: list(map())
  def build_plan(room_id, diff, opts) when is_integer(room_id) and is_map(diff) do
    opts = ensure_operation(opts)

    planner_opts =
      opts
      |> Keyword.take([
        :trace,
        :transition_ms,
        :operation,
        :group_candidate_light_ids,
        :protected_light_ids
      ])

    Planner.plan_room(room_id, diff, planner_opts)
  end

  def plan_and_enqueue(room_id, diff, opts \\ [])

  def plan_and_enqueue(_room_id, diff, _opts) when map_size(diff) == 0,
    do: {:ok, %{plan: [], planner_ms: 0}}

  @spec plan_and_enqueue(integer(), map(), keyword()) ::
          {:ok, planner_result()} | {:error, {:invalid_room_id, integer()}}
  def plan_and_enqueue(room_id, diff, opts) when is_integer(room_id) and is_map(diff) do
    opts = ensure_operation(opts)
    trace = operation_trace(opts)
    enqueue_mode = Keyword.get(opts, :enqueue_mode, :replace_targets)

    planner_started_ms = System.monotonic_time(:millisecond)
    plan = build_plan(room_id, diff, opts)
    planner_ms = System.monotonic_time(:millisecond) - planner_started_ms
    log_plan_built(trace, room_id, planner_ms, plan)
    record_planned(trace, plan, planner_ms)

    transformed_plan = attach_trace(plan, trace, System.monotonic_time(:millisecond))
    _ = enqueue_plan(transformed_plan, mode: enqueue_mode)
    log_plan_enqueued(trace, room_id, enqueue_mode, transformed_plan)
    record_enqueued(trace, transformed_plan)

    {:ok, %{plan: transformed_plan, planner_ms: planner_ms}}
  end

  def plan_and_enqueue(room_id, _diff, _opts), do: {:error, {:invalid_room_id, room_id}}

  @spec enqueue_plan(list(map()), keyword()) :: :ok
  def enqueue_plan(plan, opts \\ []) when is_list(plan) and is_list(opts) do
    _ = Executor.enqueue(plan, opts)
    :ok
  end

  @spec merge_plan_diff(map(), map()) :: map()
  def merge_plan_diff(left, right) when left == %{}, do: right
  def merge_plan_diff(left, right) when right == %{}, do: left

  def merge_plan_diff(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      Map.merge(left_value, right_value)
    end)
  end

  defp attach_trace(plan, nil, _enqueued_at_ms), do: plan

  defp attach_trace(plan, trace, enqueued_at_ms) when is_list(plan) and is_map(trace) do
    trace_id = Map.get(trace, :trace_id)
    trace_source = Map.get(trace, :source) || Map.get(trace, :trace_source)
    trace_room_id = Map.get(trace, :trace_room_id) || Map.get(trace, :room_id)
    trace_scene_id = Map.get(trace, :trace_scene_id) || Map.get(trace, :scene_id)
    trace_target_occupied = Map.get(trace, :trace_target_occupied)

    trace_started_at_ms =
      Map.get(trace, :started_at_ms) || Map.get(trace, :trace_started_at_ms)

    Enum.map(plan, fn action ->
      action
      |> Map.put(:trace_id, trace_id)
      |> Map.put(:trace_source, trace_source)
      |> maybe_put(:trace_room_id, trace_room_id)
      |> maybe_put(:trace_scene_id, trace_scene_id)
      |> maybe_put(:trace_target_occupied, trace_target_occupied)
      |> maybe_put(:trace_started_at_ms, trace_started_at_ms)
      |> Map.put(:enqueued_at_ms, enqueued_at_ms)
    end)
  end

  defp attach_trace(plan, _trace, _enqueued_at_ms), do: plan

  defp log_plan_built(nil, _room_id, _planner_ms, _plan), do: :ok

  defp log_plan_built(trace, room_id, planner_ms, plan) when is_map(trace) and is_list(plan) do
    case Map.get(trace, :trace_id) do
      nil ->
        :ok

      trace_id ->
        trace_source = Map.get(trace, :source) || Map.get(trace, :trace_source)

        DebugLogging.info(
          "[control-trace #{trace_id}] plan_built source=#{trace_source} room_id=#{inspect(room_id)} planner_ms=#{planner_ms} actions_total=#{length(plan)} group_actions=#{count_action_type(plan, :group)} light_actions=#{count_action_type(plan, :light)} off_actions=#{count_power(plan, :off)} on_actions=#{count_power(plan, :on)}"
        )
    end
  end

  defp log_plan_enqueued(nil, _room_id, _enqueue_mode, _plan), do: :ok

  defp log_plan_enqueued(trace, room_id, enqueue_mode, plan)
       when is_map(trace) and is_list(plan) do
    case Map.get(trace, :trace_id) do
      nil ->
        :ok

      trace_id ->
        trace_source = Map.get(trace, :source) || Map.get(trace, :trace_source)

        DebugLogging.info(
          "[control-trace #{trace_id}] plan_enqueued source=#{trace_source} room_id=#{inspect(room_id)} enqueue_mode=#{enqueue_mode} actions_total=#{length(plan)}"
        )
    end
  end

  defp count_action_type(actions, type) do
    Enum.count(actions, &(&1.type == type))
  end

  defp count_power(actions, power) do
    Enum.count(actions, fn action ->
      desired = Map.get(action, :desired) || %{}
      Map.get(desired, :power) == power
    end)
  end

  defp record_intent(trace, diff) when is_map(diff) do
    diff
    |> Enum.sort_by(fn {{type, id}, _desired} -> {type, id} end)
    |> Enum.each(fn {{type, id}, desired} ->
      record_trace(trace, :intent, %{
        type: type,
        id: id,
        desired: desired,
        action_count: map_size(diff)
      })
    end)
  end

  defp record_intent(_trace, _diff), do: :ok

  defp record_planned(trace, plan, planner_ms) when is_list(plan) do
    Enum.each(plan, fn action ->
      record_trace(trace, :planned, %{
        type: action.type,
        id: action.id,
        bridge_id: action.bridge_id,
        desired: action.desired,
        planner_ms: planner_ms,
        action_count: length(plan)
      })
    end)
  end

  defp record_enqueued(trace, plan) when is_list(plan) do
    Enum.each(plan, fn action ->
      record_trace(trace, :enqueued, %{
        type: action.type,
        id: action.id,
        bridge_id: action.bridge_id,
        desired: action.desired,
        action_count: length(plan)
      })
    end)

    record_trace(trace, :enqueued, %{
      action_count: length(plan),
      bridge_count: plan |> Enum.map(& &1.bridge_id) |> MapSet.new() |> MapSet.size()
    })
  end

  # Preserve the existing low-overhead path for control work that is not being traced.
  defp record_trace(%{trace_id: trace_id} = trace, stage, attrs)
       when is_binary(trace_id) and trace_id != "" do
    TraceBuffer.record(trace, stage, attrs)
  end

  defp record_trace(_trace, _stage, _attrs), do: :ok

  defp ensure_operation(opts) do
    case Keyword.get(opts, :operation) do
      %Operation{} -> opts
      _ -> Keyword.put(opts, :operation, Operation.new(opts))
    end
  end

  defp operation_trace(opts) do
    case Keyword.get(opts, :operation) do
      %Operation{trace: trace} when is_map(trace) -> trace
      _ -> Keyword.get(opts, :trace)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
