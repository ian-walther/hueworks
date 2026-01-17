defmodule Hueworks.Control.HueEventStream do
  @moduledoc """
  Manages Hue SSE connections per bridge.
  """

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Bridges.Bridge
  alias Hueworks.Control.HueEventStream.Connection
  alias Hueworks.Repo

  @restart_delay_ms 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    bridges = Repo.all(from(b in Bridge, where: b.type == :hue and b.enabled == true))
    state = %{monitors: %{}}

    state =
      Enum.reduce(bridges, state, fn bridge, acc ->
        start_connection(acc, bridge)
      end)

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
end
