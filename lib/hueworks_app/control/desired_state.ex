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

  defmodule Transaction do
    defstruct [:scene_id, :changes]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  def get(type, id) do
    case :ets.lookup(@table, {type, id}) do
      [{_key, state}] -> state
      [] -> nil
    end
  end

  def put(type, id, attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:put, type, id, attrs})
  end

  def begin(scene_id) do
    %Transaction{scene_id: scene_id, changes: %{}}
  end

  def apply(%Transaction{} = txn, type, id, attrs) when is_map(attrs) do
    key = {type, id}
    current = Map.get(txn.changes, key) || get(type, id) || %{}
    desired = normalize_desired(Map.merge(current, attrs))
    %{txn | changes: Map.put(txn.changes, key, desired)}
  end

  def commit(%Transaction{} = txn) do
    {intent_diff, reconcile_diff, updated} =
      Enum.reduce(txn.changes, {%{}, %{}, %{}}, fn
        {{type, id}, desired}, {intent_acc, reconcile_acc, updated_acc} ->
          previous_desired = get(type, id) || %{}
          _ = put(type, id, desired)
          physical = PhysicalState.get(type, id) || %{}

          intent_delta =
            diff_state(previous_desired, desired,
              brightness_tolerance: 0,
              temperature_mired_tolerance: 0
            )

          reconcile_delta =
            diff_state(physical, desired,
              brightness_tolerance: @brightness_tolerance,
              temperature_mired_tolerance: @temperature_reconcile_mired_tolerance
            )

          intent_acc =
            if intent_delta == %{} do
              intent_acc
            else
              Map.put(intent_acc, {type, id}, intent_delta)
            end

          reconcile_acc =
            if reconcile_delta == %{} do
              reconcile_acc
            else
              Map.put(reconcile_acc, {type, id}, reconcile_delta)
            end

          {intent_acc, reconcile_acc, Map.put(updated_acc, {type, id}, desired)}
      end)

    {:ok,
     %{
       intent_diff: intent_diff,
       reconcile_diff: reconcile_diff,
       updated: updated
     }}
  end

  @impl true
  def handle_call({:put, type, id, attrs}, _from, state) do
    updated = normalize_desired(Map.merge(get(type, id) || %{}, attrs))
    :ets.insert(@table, {{type, id}, updated})
    {:reply, updated, state}
  end

  defp normalize_desired(attrs) do
    case Map.get(attrs, :power) || Map.get(attrs, "power") do
      :off -> drop_light_levels(attrs)
      "off" -> drop_light_levels(attrs)
      _ -> attrs
    end
  end

  defp drop_light_levels(attrs) do
    attrs
    |> Map.delete(:brightness)
    |> Map.delete("brightness")
    |> Map.delete(:kelvin)
    |> Map.delete("kelvin")
    |> Map.delete(:temperature)
    |> Map.delete("temperature")
  end

  defp diff_state(physical, desired, opts) do
    LightStateSemantics.diff_state(physical, desired, opts)
  end
end
