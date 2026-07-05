defmodule Hueworks.Control.Executor.Convergence do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.Executor.Trace
  alias Hueworks.Control.Planner
  alias Hueworks.Repo
  alias Hueworks.Schemas.Group, as: GroupSchema
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Schemas.Light, as: LightSchema

  def handle_verification(action, state, append_fun)
      when is_function(append_fun, 2) do
    now = state.now_fn.(:millisecond)
    recovery_actions = recovery_actions_for(action, now, %{}, 1)

    case recovery_actions do
      [] ->
        Trace.log_convergence_ok(action)
        state

      actions ->
        Trace.log_convergence_retry(action, actions)
        append_fun.(state, actions)
    end
  end

  def schedule_check(action, state) do
    if action.attempts < state.max_retries do
      Process.send_after(self(), {:verify_convergence, action}, convergence_delay_ms())
    end
  end

  def stale_recovery_actions(action, state) do
    dispatched_revisions = Map.get(state, :dispatched_revisions, %{})

    state.now_fn.(:millisecond)
    |> then(&recovery_actions_for(action, &1, dispatched_revisions, 0))
  end

  defp recovery_actions_for(action, now, dispatched_revisions, attempts_increment) do
    case action_target_context(action) do
      {:ok, room_id, light_ids} ->
        diff = current_desired_diff(light_ids, dispatched_revisions)

        room_id
        |> Planner.plan_room(diff, trace: Trace.action_trace(action))
        |> Enum.map(&decorate_recovery_action(&1, action, now, attempts_increment))

      :error ->
        []
    end
  end

  defp action_target_context(%{type: :light, id: id}) when is_integer(id) do
    case Repo.get(LightSchema, id) do
      %LightSchema{room_id: room_id} -> {:ok, room_id, [id]}
      _ -> :error
    end
  end

  defp action_target_context(%{type: :group, id: id}) when is_integer(id) do
    case Repo.get(GroupSchema, id) do
      %GroupSchema{room_id: room_id} ->
        light_ids =
          Repo.all(from(gl in GroupLight, where: gl.group_id == ^id, select: gl.light_id))

        {:ok, room_id, light_ids}

      _ ->
        :error
    end
  end

  defp action_target_context(_action), do: :error

  defp current_desired_diff(light_ids, dispatched_revisions) do
    Enum.reduce(light_ids, %{}, fn light_id, acc ->
      key = {:light, light_id}
      desired = DesiredState.get(:light, light_id) || %{}
      revision = DesiredState.revision(:light, light_id)

      if desired == %{} or Map.get(dispatched_revisions, key) == revision do
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

  defp convergence_delay_ms do
    Application.get_env(:hueworks, :control_executor_convergence_delay_ms) ||
      convergence_delay_fallback()
  end

  defp convergence_delay_fallback do
    case Application.get_env(:hueworks, :manual_control_reconcile_delays_ms) do
      [delay | _] when is_integer(delay) -> delay
      delay when is_integer(delay) -> delay
      _ -> 500
    end
  end
end
