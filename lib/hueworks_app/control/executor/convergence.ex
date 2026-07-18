defmodule Hueworks.Control.Executor.Convergence do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.DispatchReceipt
  alias Hueworks.Control.Executor.Settlement
  alias Hueworks.Control.Executor.Trace
  alias Hueworks.Control.Planner
  alias Hueworks.Repo
  alias Hueworks.Schemas.Group, as: GroupSchema
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Schemas.Light, as: LightSchema

  def register_dispatch(action, %DispatchReceipt{} = receipt, completed_ms, state)
      when is_integer(completed_ms) do
    if Map.get(action, :attempts, 0) < state.max_retries do
      dispatch_id = System.unique_integer([:positive, :monotonic])

      entries =
        Settlement.entries(
          action,
          dispatch_id,
          receipt,
          completed_ms,
          state.settlement_floor_ms,
          state.settlement_grace_ms
        )

      case entries do
        [] ->
          state

        _ ->
          state = put_entries(state, entries)
          schedule_verification(dispatch_id, entries, completed_ms)
          state
      end
    else
      state
    end
  end

  def handle_verification(dispatch_id, state, append_fun)
      when is_integer(dispatch_id) and is_function(append_fun, 2) do
    state = discard_stale_entries(state, dispatch_id)
    entries = entries_for_dispatch(state, dispatch_id)

    case entries do
      [] ->
        state

      _entries ->
        now = state.now_fn.(:millisecond)
        earliest_settle_at = entries |> Enum.map(& &1.settle_at) |> Enum.min()

        if now < earliest_settle_at do
          schedule_verification(dispatch_id, entries, now)
          state
        else
          action = entries |> List.first() |> Map.fetch!(:action)
          light_ids = Enum.map(entries, & &1.light_id)
          state = remove_entries(state, entries)

          recovery_actions =
            recovery_actions_for(
              action,
              light_ids,
              now,
              %{},
              1,
              protected_light_ids(state)
            )

          case recovery_actions do
            [] ->
              Trace.log_convergence_ok(action)
              state

            actions ->
              Trace.log_convergence_retry(action, actions)
              append_fun.(state, actions)
          end
        end
    end
  end

  def stale_recovery_actions(action, state) do
    now = state.now_fn.(:millisecond)
    dispatched_revisions = Map.get(state, :dispatched_revisions, %{})

    recovery_actions_for(
      action,
      nil,
      now,
      dispatched_revisions,
      0,
      protected_light_ids(state)
    )
  end

  defp recovery_actions_for(
         action,
         requested_light_ids,
         now,
         dispatched_revisions,
         attempts_increment,
         protected_light_ids
       ) do
    case action_target_context(action) do
      {:ok, area_id, action_light_ids} ->
        light_ids = requested_light_ids || action_light_ids
        skip_dispatched? = map_size(dispatched_revisions) > 0

        diff = current_desired_diff(light_ids, dispatched_revisions, skip_dispatched?)

        area_id
        |> Planner.plan_area(
          diff,
          trace: Trace.action_trace(action),
          operation: Map.get(action, :operation),
          group_candidate_light_ids: Map.get(action, :group_candidate_light_ids),
          protected_light_ids: protected_light_ids
        )
        |> Enum.map(&decorate_recovery_action(&1, action, now, attempts_increment))

      :error ->
        []
    end
  end

  defp action_target_context(%{type: :light, id: id}) when is_integer(id) do
    case Repo.get(LightSchema, id) do
      %LightSchema{area_id: area_id} -> {:ok, area_id, [id]}
      _ -> :error
    end
  end

  defp action_target_context(%{type: :group, id: id}) when is_integer(id) do
    case Repo.get(GroupSchema, id) do
      %GroupSchema{area_id: area_id} ->
        light_ids =
          Repo.all(from(gl in GroupLight, where: gl.group_id == ^id, select: gl.light_id))

        {:ok, area_id, light_ids}

      _ ->
        :error
    end
  end

  defp action_target_context(_action), do: :error

  defp current_desired_diff(light_ids, dispatched_revisions, skip_dispatched?) do
    Enum.reduce(light_ids, %{}, fn light_id, acc ->
      key = {:light, light_id}
      desired = DesiredState.get(:light, light_id) || %{}
      revision = DesiredState.revision(:light, light_id)

      if desired == %{} or (skip_dispatched? and Map.get(dispatched_revisions, key) == revision) do
        acc
      else
        Map.put(acc, key, desired)
      end
    end)
  end

  defp decorate_recovery_action(recovery_action, action, now, attempts_increment) do
    recovery_action
    |> Map.put(:attempts, Map.get(action, :attempts, 0) + attempts_increment)
    |> Map.put(:not_before, now)
    |> Map.put(:enqueued_at_ms, now)
    |> Trace.copy_trace_metadata(action)
  end

  defp put_entries(state, entries) do
    settlements =
      Enum.reduce(entries, Map.get(state, :settlements, %{}), fn entry, acc ->
        Map.put(acc, {:light, entry.light_id}, entry)
      end)

    %{state | settlements: settlements}
  end

  defp entries_for_dispatch(state, dispatch_id) do
    state
    |> Map.get(:settlements, %{})
    |> Map.values()
    |> Enum.filter(&(&1.dispatch_id == dispatch_id))
  end

  defp discard_stale_entries(state, dispatch_id) do
    stale_entries =
      state
      |> entries_for_dispatch(dispatch_id)
      |> Enum.reject(&Settlement.current?/1)

    remove_entries(state, stale_entries)
  end

  defp remove_entries(state, entries) do
    keys = MapSet.new(Enum.map(entries, &{:light, &1.light_id}))
    settlements = Map.drop(Map.get(state, :settlements, %{}), MapSet.to_list(keys))
    %{state | settlements: settlements}
  end

  defp protected_light_ids(state) do
    state
    |> Map.get(:settlements, %{})
    |> Map.values()
    |> Enum.filter(&Settlement.current?/1)
    |> Enum.map(& &1.light_id)
    |> MapSet.new()
  end

  defp schedule_verification(dispatch_id, entries, now) do
    settle_at = entries |> Enum.map(& &1.settle_at) |> Enum.min()
    Process.send_after(self(), {:verify_settlement, dispatch_id}, max(settle_at - now, 0))
  end
end
