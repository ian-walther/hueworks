defmodule Hueworks.Control.Apply do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.{DesiredState, Executor, Planner}
  alias Hueworks.Repo
  alias Hueworks.Schemas.Light

  def commit_transaction(%DesiredState.Transaction{} = txn, opts \\ []) do
    force_apply = Keyword.get(opts, :force_apply, false)

    case DesiredState.commit(txn) do
      {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: updated}} ->
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

      other ->
        other
    end
  end

  def build_plan(room_id, diff, opts \\ [])
  def build_plan(_room_id, diff, _opts) when map_size(diff) == 0, do: []

  def build_plan(room_id, diff, opts) when is_integer(room_id) and is_map(diff) do
    Planner.plan_room(room_id, diff, trace: Keyword.get(opts, :trace))
  end

  def build_plan(_room_id, diff, _opts) when is_map(diff) do
    light_ids =
      diff
      |> Map.keys()
      |> Enum.flat_map(fn
        {:light, id} when is_integer(id) -> [id]
        {"light", id} when is_integer(id) -> [id]
        _ -> []
      end)
      |> Enum.uniq()

    bridge_by_light_id =
      Repo.all(
        from(l in Light,
          where: l.id in ^light_ids,
          select: {l.id, l.bridge_id}
        )
      )
      |> Map.new()

    diff
    |> Enum.flat_map(fn
      {{:light, id}, desired} when is_integer(id) and is_map(desired) ->
        case Map.get(bridge_by_light_id, id) do
          nil -> []
          bridge_id -> [%{type: :light, id: id, bridge_id: bridge_id, desired: desired}]
        end

      {{"light", id}, desired} when is_integer(id) and is_map(desired) ->
        case Map.get(bridge_by_light_id, id) do
          nil -> []
          bridge_id -> [%{type: :light, id: id, bridge_id: bridge_id, desired: desired}]
        end

      _ ->
        []
    end)
  end

  def enqueue_plan(plan) when is_list(plan) do
    _ = Executor.enqueue(plan)
    :ok
  end

  def merge_plan_diff(left, right) when left == %{}, do: right
  def merge_plan_diff(left, right) when right == %{}, do: left

  def merge_plan_diff(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      Map.merge(left_value, right_value)
    end)
  end
end
