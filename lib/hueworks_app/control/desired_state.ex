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

    desired =
      current
      |> Map.merge(attrs)
      |> normalize_desired(attrs)

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
    updated =
      get(type, id)
      |> Kernel.||(%{})
      |> Map.merge(attrs)
      |> normalize_desired(attrs)

    :ets.insert(@table, {{type, id}, updated})
    {:reply, updated, state}
  end

  defp normalize_desired(attrs, incoming_attrs) do
    attrs = harmonize_color_and_temperature(attrs, incoming_attrs)

    case Map.get(attrs, :power) || Map.get(attrs, "power") do
      :off -> drop_light_levels(attrs)
      "off" -> drop_light_levels(attrs)
      _ -> attrs
    end
  end

  defp harmonize_color_and_temperature(attrs, incoming_attrs)
       when is_map(attrs) and is_map(incoming_attrs) do
    cond do
      incoming_has_xy?(incoming_attrs) ->
        drop_kelvin(attrs)

      incoming_has_kelvin?(incoming_attrs) ->
        drop_xy(attrs)

      true ->
        attrs
    end
  end

  defp harmonize_color_and_temperature(attrs, _incoming_attrs), do: attrs

  defp drop_light_levels(attrs) do
    attrs
    |> Map.delete(:brightness)
    |> Map.delete("brightness")
    |> Map.delete(:kelvin)
    |> Map.delete("kelvin")
    |> Map.delete(:temperature)
    |> Map.delete("temperature")
    |> Map.delete(:x)
    |> Map.delete("x")
    |> Map.delete(:y)
    |> Map.delete("y")
  end

  defp drop_kelvin(attrs) do
    attrs
    |> Map.delete(:kelvin)
    |> Map.delete("kelvin")
    |> Map.delete(:temperature)
    |> Map.delete("temperature")
  end

  defp drop_xy(attrs) do
    attrs
    |> Map.delete(:x)
    |> Map.delete("x")
    |> Map.delete(:y)
    |> Map.delete("y")
  end

  defp incoming_has_xy?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, :x) or Map.has_key?(attrs, "x") or Map.has_key?(attrs, :y) or
      Map.has_key?(attrs, "y")
  end

  defp incoming_has_xy?(_attrs), do: false

  defp incoming_has_kelvin?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, :kelvin) or Map.has_key?(attrs, "kelvin") or
      Map.has_key?(attrs, :temperature) or Map.has_key?(attrs, "temperature")
  end

  defp incoming_has_kelvin?(_attrs), do: false

  defp diff_state(physical, desired, opts) do
    LightStateSemantics.diff_state(physical, desired, opts)
  end
end
