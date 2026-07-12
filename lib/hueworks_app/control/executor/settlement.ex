defmodule Hueworks.Control.Executor.Settlement do
  @moduledoc false

  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.DispatchReceipt
  alias Hueworks.Control.Operation

  @enforce_keys [
    :operation_id,
    :dispatch_id,
    :light_id,
    :desired_revision,
    :effective_transition_ms,
    :settle_at,
    :action
  ]
  defstruct [
    :operation_id,
    :dispatch_id,
    :light_id,
    :desired_revision,
    :transition_policy,
    :effective_transition_ms,
    :settle_at,
    :action
  ]

  def entries(action, dispatch_id, %DispatchReceipt{} = receipt, completed_ms, floor_ms, grace_ms)
      when is_integer(completed_ms) and is_integer(floor_ms) and is_integer(grace_ms) do
    settle_at = completed_ms + max(receipt.effective_transition_ms + grace_ms, floor_ms)

    Enum.map(Map.get(action, :light_ids, []), fn light_id ->
      %__MODULE__{
        operation_id: operation_id(action),
        dispatch_id: dispatch_id,
        light_id: light_id,
        desired_revision: desired_revision(action, light_id),
        transition_policy: transition_policy(action),
        effective_transition_ms: receipt.effective_transition_ms,
        settle_at: settle_at,
        action: action
      }
    end)
  end

  def current?(%__MODULE__{light_id: light_id, desired_revision: revision}) do
    DesiredState.revision(:light, light_id) == revision
  end

  defp operation_id(%{operation: %Operation{id: id}}), do: id
  defp operation_id(_action), do: nil

  defp transition_policy(%{operation: %Operation{transition_policy: policy}}), do: policy
  defp transition_policy(_action), do: nil

  defp desired_revision(%{desired_revisions: revisions}, light_id) when is_map(revisions) do
    Map.get(revisions, {:light, light_id}, DesiredState.revision(:light, light_id))
  end

  defp desired_revision(_action, light_id), do: DesiredState.revision(:light, light_id)
end
