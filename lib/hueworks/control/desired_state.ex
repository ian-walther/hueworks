defmodule Hueworks.Control.DesiredState do
  @moduledoc """
  Desired control state stored in-memory and updated via transactions.
  """

  use GenServer

  alias Hueworks.Control.State, as: PhysicalState

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

  def sync(type, id, attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:sync, type, id, attrs})
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
    {diff, updated} =
      Enum.reduce(txn.changes, {%{}, %{}}, fn {{type, id}, desired}, {diff_acc, updated_acc} ->
        _ = put(type, id, desired)
        physical = PhysicalState.get(type, id) || %{}
        delta = diff_state(physical, desired)

        diff_acc =
          if delta == %{} do
            diff_acc
          else
            Map.put(diff_acc, {type, id}, delta)
          end

        {diff_acc, Map.put(updated_acc, {type, id}, desired)}
      end)

    {:ok, diff, updated}
  end

  @impl true
  def handle_call({:put, type, id, attrs}, _from, state) do
    updated = normalize_desired(Map.merge(get(type, id) || %{}, attrs))
    :ets.insert(@table, {{type, id}, updated})
    {:reply, updated, state}
  end

  @impl true
  def handle_call({:sync, type, id, attrs}, _from, state) do
    updated = normalize_desired(attrs)
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

  defp diff_state(physical, desired) do
    desired
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if Map.get(physical, key) == value do
        acc
      else
        Map.put(acc, key, value)
      end
    end)
  end
end
