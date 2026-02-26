defmodule Hueworks.Subscription.CasetaEventStream do
  @moduledoc """
  Manages Caseta LEAP connections per bridge.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Subscription.CasetaEventStream.Connection
  alias Hueworks.Subscription.Readiness

  @restart_delay_ms 1_000
  @retry_delay_ms 2_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    state = %{monitors: %{}}

    state = maybe_start_connections(state)

    {:ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {bridge, monitors} ->
        Process.send_after(self(), {:restart, bridge}, @restart_delay_ms)
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
    case Connection.start_link(bridge) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        %{state | monitors: Map.put(state.monitors, ref, bridge)}

      {:error, _reason} ->
        Process.send_after(self(), {:restart, bridge}, @restart_delay_ms)
        state
    end
  end

  defp maybe_start_connections(state) do
    if Readiness.bridges_table_ready?() do
      bridges = Repo.all(from(b in Bridge, where: b.type == :caseta and b.enabled == true))

      Enum.reduce(bridges, state, fn bridge, acc ->
        start_connection(acc, bridge)
      end)
    else
      Process.send_after(self(), :retry_bootstrap, @retry_delay_ms)
      state
    end
  end
end
