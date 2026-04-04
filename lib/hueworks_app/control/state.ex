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

  def get(type, id) do
    case :ets.lookup(@table, {type, id}) do
      [{_key, state}] -> state
      [] -> nil
    end
  end

  def ensure(type, id, defaults) when is_map(defaults) do
    GenServer.call(__MODULE__, {:ensure, type, id, defaults})
  end

  def put(type, id, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    GenServer.call(__MODULE__, {:put, type, id, attrs, self(), opts})
  end

  def bootstrap do
    GenServer.cast(__MODULE__, :bootstrap)
  end

  def suppress_scene_clear_for_refresh, do: :ok

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

    updated = Map.merge(current, attrs)
    :ets.insert(@table, {key, updated})
    broadcast_update(key, updated)
    updated
  end

  defp broadcast_update({type, id}, state) do
    PubSub.broadcast(Hueworks.PubSub, @topic, {:control_state, type, id, state})
  end
end
