defmodule Hueworks.Control.State do
  @moduledoc """
  Shared in-memory control state backed by ETS.
  """

  use GenServer
  require Logger

  alias Hueworks.Control.Bootstrap.HomeAssistant
  alias Hueworks.Control.Bootstrap.Hue
  alias Hueworks.Control.Bootstrap.Z2M
  alias Hueworks.Control.LightStateSemantics
  alias Phoenix.PubSub

  @table :hueworks_control_state
  @topic "control_state"

  @type entity_type :: atom()
  @type entity_id :: term()
  @type state_map :: map()

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

    {:ok, %{bootstrap_ref: nil, bootstrap_pid: nil, bootstrap_waiters: []},
     {:continue, :bootstrap}}
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

  @spec put(entity_type(), entity_id(), state_map()) :: state_map()
  def put(type, id, attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:put, type, id, attrs})
  end

  @spec bootstrap() :: :ok
  def bootstrap do
    GenServer.call(__MODULE__, :bootstrap, :infinity)
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    {:noreply, start_bootstrap(state)}
  end

  @impl true
  def handle_call({:ensure, type, id, defaults}, _from, state) do
    key = {type, id}
    defaults = LightStateSemantics.normalize_keys(defaults)

    case :ets.lookup(@table, key) do
      [{_key, current}] ->
        {:reply, current, state}

      [] ->
        :ets.insert(@table, {key, defaults})
        {:reply, defaults, state}
    end
  end

  @impl true
  def handle_call({:put, type, id, attrs}, _from, state) do
    key = {type, id}

    updated = merge_and_store(key, attrs)
    {:reply, updated, state}
  end

  @impl true
  def handle_call(:bootstrap, from, state) do
    state =
      state
      |> start_bootstrap()
      |> enqueue_bootstrap_waiter(from)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{bootstrap_ref: ref} = state) do
    result = if(reason == :normal, do: :ok, else: {:error, reason})

    state.bootstrap_waiters
    |> Enum.reverse()
    |> Enum.each(&GenServer.reply(&1, result))

    {:noreply, %{state | bootstrap_ref: nil, bootstrap_pid: nil, bootstrap_waiters: []}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if is_pid(state.bootstrap_pid) and Process.alive?(state.bootstrap_pid) do
      Process.exit(state.bootstrap_pid, :shutdown)
    end

    :ok
  end

  defp do_bootstrap do
    bootstrap_modules()
    |> Enum.each(&run_bootstrap_module/1)

    :ok
  end

  defp start_bootstrap(%{bootstrap_ref: ref} = state) when not is_nil(ref), do: state

  defp start_bootstrap(state) do
    {pid, ref} =
      spawn_monitor(fn ->
        _ = do_bootstrap()
      end)

    %{state | bootstrap_pid: pid, bootstrap_ref: ref}
  end

  defp enqueue_bootstrap_waiter(state, from) do
    %{state | bootstrap_waiters: [from | state.bootstrap_waiters]}
  end

  defp bootstrap_modules do
    Application.get_env(
      :hueworks,
      :control_state_bootstrap_modules,
      [Hue, HomeAssistant, Z2M]
    )
  end

  defp run_bootstrap_module(module) when is_atom(module) do
    module.run()
  rescue
    error ->
      Logger.error("""
      Control state bootstrap failed in #{inspect(module)}: #{Exception.message(error)}
      #{Exception.format_stacktrace(__STACKTRACE__)}
      """)
  end

  defp run_bootstrap_module({module, arg}) when is_atom(module) do
    module.run(arg)
  rescue
    error ->
      Logger.error("""
      Control state bootstrap failed in #{inspect({module, arg})}: #{Exception.message(error)}
      #{Exception.format_stacktrace(__STACKTRACE__)}
      """)
  end

  defp merge_and_store(key, attrs) do
    current =
      case :ets.lookup(@table, key) do
        [{_key, existing}] -> existing
        [] -> %{}
      end

    updated =
      current
      |> LightStateSemantics.merge_state(attrs)

    :ets.insert(@table, {key, updated})
    broadcast_update(key, updated)
    updated
  end

  defp broadcast_update({type, id}, state) do
    PubSub.broadcast(Hueworks.PubSub, @topic, {:control_state, type, id, state})
  end
end
