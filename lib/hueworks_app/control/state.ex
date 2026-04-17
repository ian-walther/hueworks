defmodule Hueworks.Control.State do
  @moduledoc """
  Shared in-memory control state backed by ETS.
  """

  use GenServer

  alias Hueworks.Control.Bootstrap.HomeAssistant
  alias Hueworks.Control.Bootstrap.Hue
  alias Hueworks.Control.Bootstrap.Z2M
  alias Phoenix.PubSub

  @table :hueworks_control_state
  @topic "control_state"

  @type entity_type :: atom()
  @type entity_id :: term()
  @type state_map :: map()
  @type put_opts :: keyword()

  @spec start_link(term()) :: GenServer.on_start()

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}, {:continue, :bootstrap}}
  end

  @spec get(entity_type(), entity_id()) :: state_map() | nil
  def get(type, id) do
    case :ets.lookup(@table, {type, id}) do
      [{_key, state}] -> state
      [] -> nil
    end
  end

  @spec ensure(entity_type(), entity_id(), state_map()) :: state_map()
  def ensure(type, id, defaults) when is_map(defaults) do
    GenServer.call(__MODULE__, {:ensure, type, id, defaults})
  end

  @spec put(entity_type(), entity_id(), state_map(), put_opts()) :: state_map()
  def put(type, id, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    GenServer.call(__MODULE__, {:put, type, id, attrs, self(), opts})
  end

  @spec bootstrap() :: :ok
  def bootstrap do
    GenServer.cast(__MODULE__, :bootstrap)
  end

  @spec suppress_scene_clear_for_refresh() :: :ok
  def suppress_scene_clear_for_refresh, do: :ok

  @spec clear_scene_clear_suppression() :: :ok
  def clear_scene_clear_suppression, do: :ok

  @impl true
  def handle_continue(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end

  @impl true
  def handle_call({:ensure, type, id, defaults}, _from, state) do
    key = {type, id}

    case :ets.lookup(@table, key) do
      [{_key, current}] ->
        {:reply, current, state}

      [] ->
        :ets.insert(@table, {key, defaults})
        {:reply, defaults, state}
    end
  end

  @impl true
  def handle_call({:put, type, id, attrs, caller, opts}, _from, state) do
    key = {type, id}

    _ = caller
    _ = opts
    updated = merge_and_store(key, attrs)
    {:reply, updated, state}
  end

  @impl true
  def handle_cast(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end

  defp do_bootstrap do
    Task.start(fn ->
      Hue.run()
      HomeAssistant.run()
      Z2M.run()
    end)
  end

  defp merge_and_store(key, attrs) do
    current =
      case :ets.lookup(@table, key) do
        [{_key, existing}] -> existing
        [] -> %{}
      end

    updated =
      current
      |> harmonize_color_and_temperature(attrs)
      |> Map.merge(attrs)

    :ets.insert(@table, {key, updated})
    broadcast_update(key, updated)
    updated
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

  defp broadcast_update({type, id}, state) do
    PubSub.broadcast(Hueworks.PubSub, @topic, {:control_state, type, id, state})
  end
end
