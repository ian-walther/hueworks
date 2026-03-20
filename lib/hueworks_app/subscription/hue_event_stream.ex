defmodule Hueworks.Subscription.HueEventStream do
  @moduledoc """
  Manages Hue SSE connections per bridge.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Schemas.Bridge
  alias Hueworks.Subscription.HueEventStream.Connection
  alias Hueworks.Subscription.Readiness
  alias Hueworks.Repo

  @restart_delay_ms 1_000
  @retry_delay_ms 2_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %{
      monitors: %{},
      connection_module: Keyword.get(opts, :connection_module, Connection),
      readiness_fun: Keyword.get(opts, :readiness_fun, &Readiness.bridges_table_ready?/0),
      restart_delay_ms: Keyword.get(opts, :restart_delay_ms, @restart_delay_ms),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @retry_delay_ms)
    }

    state = maybe_start_connections(state)

    {:ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {bridge, monitors} ->
        Process.send_after(self(), {:restart, bridge}, state.restart_delay_ms)
        {:noreply, %{state | monitors: monitors}}
    end
  end

  @impl true
  def handle_info({:restart, bridge}, state) do
    {:noreply, start_connection(state, bridge)}
  end

  @impl true
  def handle_info(:retry_bootstrap, state) do
    {:noreply, maybe_start_connections(state)}
  end

  defp start_connection(state, bridge) do
    case state.connection_module.start_link(bridge) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        %{state | monitors: Map.put(state.monitors, ref, bridge)}

      {:error, _reason} ->
        Process.send_after(self(), {:restart, bridge}, state.restart_delay_ms)
        state
    end
  end

  defp maybe_start_connections(state) do
    if state.readiness_fun.() do
      bridges = Repo.all(from(b in Bridge, where: b.type == :hue and b.enabled == true))

      Enum.reduce(bridges, state, fn bridge, acc ->
        start_connection(acc, bridge)
      end)
    else
      Process.send_after(self(), :retry_bootstrap, state.retry_delay_ms)
      state
    end
  end
end
