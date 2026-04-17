defmodule Hueworks.Control.Apply do
  @moduledoc false

  alias Hueworks.DebugLogging
  alias Hueworks.Control.{DesiredState, Executor, Planner}

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
    force_apply = Keyword.get(opts, :force_apply, false)
    {:ok, %{plan_diff: plan_diff} = result} = commit_transaction(txn, force_apply: force_apply)

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
    planner_opts =
      opts
      |> Keyword.take([:trace, :transition_ms])

    Planner.plan_room(room_id, diff, planner_opts)
  end

  def plan_and_enqueue(room_id, diff, opts \\ [])

  def plan_and_enqueue(_room_id, diff, _opts) when map_size(diff) == 0,
    do: {:ok, %{plan: [], planner_ms: 0}}

  @spec plan_and_enqueue(integer(), map(), keyword()) ::
          {:ok, planner_result()} | {:error, {:invalid_room_id, integer()}}
  def plan_and_enqueue(room_id, diff, opts) when is_integer(room_id) and is_map(diff) do
    trace = Keyword.get(opts, :trace)
    enqueue_mode = Keyword.get(opts, :enqueue_mode, :replace)

    planner_started_ms = System.monotonic_time(:millisecond)
    plan = build_plan(room_id, diff, trace: trace)
    planner_ms = System.monotonic_time(:millisecond) - planner_started_ms
    log_plan_built(trace, room_id, planner_ms, plan)

    transformed_plan = attach_trace(plan, trace, System.monotonic_time(:millisecond))
    _ = enqueue_plan(transformed_plan, mode: enqueue_mode)
    log_plan_enqueued(trace, room_id, enqueue_mode, transformed_plan)

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
    trace_id = map_value(trace, :trace_id)
    trace_source = map_value(trace, :source) || map_value(trace, :trace_source)
    trace_room_id = map_value(trace, :trace_room_id)
    trace_scene_id = map_value(trace, :trace_scene_id)
    trace_target_occupied = map_value(trace, :trace_target_occupied)

    trace_started_at_ms =
      map_value(trace, :started_at_ms) || map_value(trace, :trace_started_at_ms)

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
    case map_value(trace, :trace_id) do
      nil ->
        :ok

      trace_id ->
        trace_source = map_value(trace, :source) || map_value(trace, :trace_source)

        DebugLogging.info(
          "[occ-trace #{trace_id}] plan_built source=#{trace_source} room_id=#{inspect(room_id)} planner_ms=#{planner_ms} actions_total=#{length(plan)} group_actions=#{count_action_type(plan, :group)} light_actions=#{count_action_type(plan, :light)} off_actions=#{count_power(plan, :off)} on_actions=#{count_power(plan, :on)}"
        )
    end
  end

  defp log_plan_enqueued(nil, _room_id, _enqueue_mode, _plan), do: :ok

  defp log_plan_enqueued(trace, room_id, enqueue_mode, plan)
       when is_map(trace) and is_list(plan) do
    case map_value(trace, :trace_id) do
      nil ->
        :ok

      trace_id ->
        trace_source = map_value(trace, :source) || map_value(trace, :trace_source)

        DebugLogging.info(
          "[occ-trace #{trace_id}] plan_enqueued source=#{trace_source} room_id=#{inspect(room_id)} enqueue_mode=#{enqueue_mode} actions_total=#{length(plan)}"
        )
    end
  end

  defp count_action_type(actions, type) do
    Enum.count(actions, &(&1.type == type))
  end

  defp count_power(actions, power) do
    Enum.count(actions, fn action ->
      desired = Map.get(action, :desired) || %{}
      (Map.get(desired, :power) || Map.get(desired, "power")) == power
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
