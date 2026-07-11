defmodule Hueworks.Control.DesiredState do
  @moduledoc """
  Desired control state stored in-memory and updated via transactions.
  """

  use GenServer

  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.State, as: PhysicalState

  @brightness_tolerance 2
  @temperature_reconcile_mired_tolerance 1

  @table :hueworks_desired_state
  @revision_table :hueworks_desired_state_revisions
  @updated_at_table :hueworks_desired_state_updated_at

  @type entity_type :: atom()
  @type entity_id :: term()
  @type attrs_map :: map()
  @type entity_key :: {entity_type(), entity_id()}
  @type diff_map :: %{optional(entity_key()) => attrs_map()}
  @type commit_result :: %{
          intent_diff: diff_map(),
          reconcile_diff: diff_map(),
          updated: diff_map(),
          revisions: %{optional(entity_key()) => non_neg_integer()}
        }

  defmodule Transaction do
    defstruct [:scene_id, :changes]
  end

  @type transaction :: %Transaction{
          scene_id: term(),
          changes: %{optional(entity_key()) => attrs_map()}
        }

  @spec start_link(term()) :: GenServer.on_start()

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    if :ets.whereis(@revision_table) != :undefined do
      :ets.delete(@revision_table)
    end

    if :ets.whereis(@updated_at_table) != :undefined do
      :ets.delete(@updated_at_table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])

    :ets.new(@revision_table, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@updated_at_table, [:named_table, :public, read_concurrency: true])

    {:ok, %{}}
  end

  @spec get(entity_type(), entity_id()) :: attrs_map() | nil
  def get(type, id) do
    case :ets.lookup(@table, {type, id}) do
      [{_key, state}] -> state
      [] -> nil
    end
  end

  @spec put(entity_type(), entity_id(), attrs_map()) :: attrs_map()
  def put(type, id, attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:put, type, id, attrs})
  end

  @spec revision(entity_type(), entity_id()) :: non_neg_integer()
  def revision(type, id) do
    case :ets.lookup(@revision_table, {type, id}) do
      [{_key, revision}] -> revision
      [] -> 0
    end
  end

  def updated_at(type, id) do
    case :ets.lookup(@updated_at_table, {type, id}) do
      [{_key, timestamp}] -> timestamp
      [] -> nil
    end
  end

  @spec snapshot([entity_key()]) :: %{states: diff_map(), revisions: map()}
  def snapshot(keys) when is_list(keys) do
    GenServer.call(__MODULE__, {:snapshot, keys})
  end

  @spec action_current?(map()) :: boolean()
  def action_current?(%{desired_revisions: revisions}) when is_map(revisions) do
    Enum.all?(revisions, fn {{type, id}, planned_revision} ->
      revision(type, id) == planned_revision
    end)
  end

  def action_current?(_action), do: true

  @spec begin(term()) :: transaction()
  def begin(scene_id) do
    %Transaction{scene_id: scene_id, changes: %{}}
  end

  @spec apply(transaction(), entity_type(), entity_id(), attrs_map()) :: transaction()
  def apply(%Transaction{} = txn, type, id, attrs) when is_map(attrs) do
    key = {type, id}
    current = Map.get(txn.changes, key) || get(type, id) || %{}

    desired =
      current
      |> LightStateSemantics.merge_state(attrs)
      |> LightStateSemantics.normalize_power_off()

    %{txn | changes: Map.put(txn.changes, key, desired)}
  end

  @spec commit(transaction()) :: {:ok, commit_result()}
  def commit(%Transaction{} = txn) do
    GenServer.call(__MODULE__, {:commit, txn})
  end

  @impl true
  def handle_call({:put, type, id, attrs}, _from, state) do
    {updated, _revision} = put_state(type, id, attrs)
    {:reply, updated, state}
  end

  def handle_call({:commit, %Transaction{} = txn}, _from, state) do
    {intent_diff, reconcile_diff, updated, revisions} =
      Enum.reduce(txn.changes, {%{}, %{}, %{}, %{}}, fn
        {{type, id}, desired}, {intent_acc, reconcile_acc, updated_acc, revision_acc} ->
          previous_desired = get(type, id) || %{}
          {committed_desired, committed_revision} = put_state(type, id, desired)
          physical = PhysicalState.get(type, id) || %{}

          intent_delta =
            diff_state(previous_desired, committed_desired,
              brightness_tolerance: 0,
              temperature_mired_tolerance: 0
            )

          reconcile_delta =
            diff_state(physical, committed_desired,
              brightness_tolerance: @brightness_tolerance,
              temperature_mired_tolerance: @temperature_reconcile_mired_tolerance
            )

          intent_acc = maybe_put_diff(intent_acc, {type, id}, intent_delta)
          reconcile_acc = maybe_put_diff(reconcile_acc, {type, id}, reconcile_delta)

          {
            intent_acc,
            reconcile_acc,
            Map.put(updated_acc, {type, id}, committed_desired),
            Map.put(revision_acc, {type, id}, committed_revision)
          }
      end)

    {:reply,
     {:ok,
      %{
        intent_diff: intent_diff,
        reconcile_diff: reconcile_diff,
        updated: updated,
        revisions: revisions
      }}, state}
  end

  def handle_call({:snapshot, keys}, _from, state) do
    snapshot = %{
      states:
        Map.new(keys, fn {type, id} = key ->
          {key, get(type, id)}
        end),
      revisions:
        Map.new(keys, fn {type, id} = key ->
          {key, revision(type, id)}
        end),
      updated_at:
        Map.new(keys, fn {type, id} = key ->
          {key, updated_at(type, id)}
        end)
    }

    {:reply, snapshot, state}
  end

  defp put_state(type, id, attrs) do
    previous = get(type, id) || %{}

    updated =
      previous
      |> LightStateSemantics.merge_state(attrs)
      |> LightStateSemantics.normalize_power_off()

    :ets.insert(@table, {{type, id}, updated})

    revision =
      if updated == previous do
        revision(type, id)
      else
        next_revision = revision(type, id) + 1
        :ets.insert(@revision_table, {{type, id}, next_revision})
        :ets.insert(@updated_at_table, {{type, id}, DateTime.utc_now()})
        next_revision
      end

    {updated, revision}
  end

  defp maybe_put_diff(acc, _key, delta) when delta == %{}, do: acc
  defp maybe_put_diff(acc, key, delta), do: Map.put(acc, key, delta)

  defp diff_state(physical, desired, opts) do
    LightStateSemantics.diff_state(physical, desired, opts)
  end
end
