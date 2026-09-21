defmodule Hueworks.Subscription.GenericEventStream do
  @moduledoc false

  use GenServer

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Subscription.Readiness

  @restart_delay_ms 1_000
  @retry_delay_ms 2_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def refresh(server, bridge_id), do: GenServer.call(server, {:refresh, bridge_id}, 10_000)

  @impl true
  def handle_call({:refresh, bridge_id}, _from, state) do
    case Repo.get(Bridge, bridge_id) do
      %Bridge{enabled: true, type: type} = bridge when type == state.bridge_type ->
        refresh_bridge(state, bridge)

      _ ->
        {:reply, {:error, :bridge_unavailable}, state}
    end
  end

  defp refresh_bridge(state, bridge) do
    if Hueworks.RuntimeIO.disabled?() do
      {:reply, {:error, :runtime_io_disabled}, state}
    else
      state = start_connection(state, bridge)

      case connection_for(state, bridge.id) do
        nil -> {:reply, {:error, :connection_unavailable}, state}
        {ref, pid} -> refresh_tracked_connection(state, bridge, ref, pid)
      end
    end
  end

  defp refresh_tracked_connection(state, bridge, ref, pid) do
    case refresh_connection(state.connection_module, pid, bridge) do
      {:ok, ^pid} ->
        {:reply, :ok, state}

      {:ok, replacement} ->
        Process.demonitor(ref, [:flush])
        state = forget_connection(state, ref, pid)
        {:reply, :ok, track_connection(state, bridge, replacement)}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      bridge_type: Keyword.fetch!(opts, :bridge_type),
      monitors: %{},
      connection_refs: %{},
      connection_module: Keyword.fetch!(opts, :connection_module),
      readiness_fun: Keyword.get(opts, :readiness_fun, &Readiness.bridges_table_ready?/0),
      restart_delay_ms: Keyword.get(opts, :restart_delay_ms, @restart_delay_ms),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @retry_delay_ms)
    }

    state = maybe_start_connections(state)

    {:ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply,
         %{state | monitors: monitors, connection_refs: Map.delete(state.connection_refs, pid)}}

      {bridge, monitors} ->
        Process.send_after(self(), {:restart, bridge}, state.restart_delay_ms)

        {:noreply,
         %{state | monitors: monitors, connection_refs: Map.delete(state.connection_refs, pid)}}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    if Map.has_key?(state.connection_refs, pid) do
      {:noreply, state}
    else
      {:stop, reason, state}
    end
  end

  @impl true
  def handle_info({:restart, bridge}, state) do
    case Repo.get(Bridge, bridge.id) do
      %Bridge{enabled: true} = current -> {:noreply, start_connection(state, current)}
      _ -> {:noreply, state}
    end
  end

  @impl true
  def handle_info(:retry_bootstrap, state) do
    {:noreply, maybe_start_connections(state)}
  end

  defp start_connection(state, bridge) do
    if connection_for(state, bridge.id) do
      state
    else
      do_start_connection(state, bridge)
    end
  end

  defp do_start_connection(state, bridge) do
    case state.connection_module.start_link(bridge) do
      {:ok, pid} ->
        track_connection(state, bridge, pid)

      {:error, _reason} ->
        Process.send_after(self(), {:restart, bridge}, state.restart_delay_ms)
        state
    end
  end

  defp connection_for(state, bridge_id) do
    Enum.find_value(state.connection_refs, fn {pid, ref} ->
      if state.monitors[ref].id == bridge_id and Process.alive?(pid), do: {ref, pid}
    end)
  end

  defp track_connection(state, bridge, pid) do
    ref = Process.monitor(pid)

    %{
      state
      | monitors: Map.put(state.monitors, ref, bridge),
        connection_refs: Map.put(state.connection_refs, pid, ref)
    }
  end

  defp forget_connection(state, ref, pid) do
    %{
      state
      | monitors: Map.delete(state.monitors, ref),
        connection_refs: Map.delete(state.connection_refs, pid)
    }
  end

  defp refresh_connection(module, pid, bridge) do
    module.refresh(pid, bridge)
  catch
    :exit, _ -> {:error, :connection_unavailable}
  end

  defp maybe_start_connections(state) do
    if state.readiness_fun.() do
      state.bridge_type
      |> load_enabled_bridges()
      |> Enum.reduce(state, fn bridge, acc ->
        start_connection(acc, bridge)
      end)
    else
      Process.send_after(self(), :retry_bootstrap, state.retry_delay_ms)
      state
    end
  end

  defp load_enabled_bridges(type) do
    Repo.all(from(b in Bridge, where: b.type == ^type and b.enabled == true))
  end
end
