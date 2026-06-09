defmodule Hueworks.HomeKit.Bridge do
  @moduledoc false

  use GenServer
  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeKit.AccessoryGraph
  alias Phoenix.PubSub

  @control_topic "control_state"
  @idle_pair_setup_step 1
  @default_pairing_timeout_ms 30_000
  @default_pairing_watchdog_interval_ms 5_000

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def reload, do: maybe_cast(:reload)

  def put_change_token(opts, change_token) when is_list(opts) do
    maybe_cast({:put_change_token, token_key(opts), change_token})
  end

  def status do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, :status)
      _ -> %{running?: false, topology_hash: nil}
    end
  end

  @impl true
  def init(_opts) do
    PubSub.subscribe(Hueworks.PubSub, @control_topic)
    PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())
    schedule_pairing_watchdog()

    {:ok, %{hap_pid: nil, topology_hash: nil, change_tokens: %{}, pairing_busy_since_ms: nil},
     {:continue, :reload}}
  end

  @impl true
  def handle_continue(:reload, state), do: {:noreply, rebuild(state)}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{running?: is_pid(state.hap_pid), topology_hash: state.topology_hash}, state}
  end

  @impl true
  def handle_cast(:reload, state), do: {:noreply, rebuild(state)}

  def handle_cast({:put_change_token, key, change_token}, state) do
    {:noreply, put_in(state.change_tokens[key], change_token)}
  end

  @impl true
  def handle_info({:control_state, kind, id, _control_state}, state)
      when kind in [:light, :group] and is_integer(id) do
    state.change_tokens
    |> Enum.filter(fn
      {{:entity, ^kind, ^id, _characteristic}, _token} -> true
      _ -> false
    end)
    |> Enum.each(fn {_key, token} -> notify_change_token(token) end)

    {:noreply, state}
  end

  def handle_info({:active_scene_updated, _room_id, _scene_id}, state) do
    state.change_tokens
    |> Enum.filter(fn
      {{:scene, _scene_id}, _token} -> true
      _ -> false
    end)
    |> Enum.each(fn {_key, token} -> notify_change_token(token) end)

    {:noreply, state}
  end

  def handle_info(:pairing_watchdog, state) do
    schedule_pairing_watchdog()
    {:noreply, maybe_restart_stuck_pairing(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp rebuild(state) do
    case AccessoryGraph.build() do
      {:disabled, _topology} ->
        state
        |> stop_hap()
        |> Map.merge(%{topology_hash: nil, change_tokens: %{}, pairing_busy_since_ms: nil})

      {:ok, accessory_server, topology} ->
        hash = AccessoryGraph.topology_hash(topology)

        if hash == state.topology_hash and is_pid(state.hap_pid) do
          state
        else
          state
          |> stop_hap()
          |> start_hap(accessory_server, hash)
        end
    end
  end

  defp start_hap(state, accessory_server, topology_hash) do
    case hap_module().start_link(accessory_server) do
      {:ok, pid} ->
        Logger.info(
          "Started HomeKit bridge with #{length(accessory_server.accessories)} accessories"
        )

        %{
          state
          | hap_pid: pid,
            topology_hash: topology_hash,
            change_tokens: %{},
            pairing_busy_since_ms: nil
        }

      {:error, {:already_started, pid}} ->
        %{
          state
          | hap_pid: pid,
            topology_hash: topology_hash,
            change_tokens: %{},
            pairing_busy_since_ms: nil
        }

      {:error, reason} ->
        Logger.warning("Unable to start HomeKit bridge: #{inspect(reason)}")

        %{
          state
          | hap_pid: nil,
            topology_hash: nil,
            change_tokens: %{},
            pairing_busy_since_ms: nil
        }
    end
  end

  defp stop_hap(%{hap_pid: nil} = state), do: state

  defp stop_hap(%{hap_pid: pid} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      _ = Supervisor.stop(pid, :normal, 5_000)
    end

    %{state | hap_pid: nil, pairing_busy_since_ms: nil}
  catch
    :exit, _reason -> %{state | hap_pid: nil, pairing_busy_since_ms: nil}
  end

  defp maybe_restart_stuck_pairing(%{hap_pid: pid} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      check_pairing_progress(state)
    else
      %{state | hap_pid: nil, pairing_busy_since_ms: nil}
    end
  end

  defp maybe_restart_stuck_pairing(state), do: %{state | pairing_busy_since_ms: nil}

  defp check_pairing_progress(state) do
    case pair_setup_step() do
      {:ok, @idle_pair_setup_step} ->
        %{state | pairing_busy_since_ms: nil}

      {:ok, step} ->
        handle_busy_pair_setup(state, step)

      {:error, reason} ->
        Logger.debug("Unable to inspect HomeKit pair setup state: #{inspect(reason)}")
        %{state | pairing_busy_since_ms: nil}
    end
  end

  defp handle_busy_pair_setup(%{pairing_busy_since_ms: nil} = state, step) do
    now = monotonic_ms()

    if pairing_timeout_ms() <= 0 do
      restart_stuck_pairing(state, step, 0)
    else
      %{state | pairing_busy_since_ms: now}
    end
  end

  defp handle_busy_pair_setup(%{pairing_busy_since_ms: busy_since} = state, step) do
    elapsed_ms = monotonic_ms() - busy_since

    if elapsed_ms >= pairing_timeout_ms() do
      restart_stuck_pairing(state, step, elapsed_ms)
    else
      state
    end
  end

  defp restart_stuck_pairing(state, step, elapsed_ms) do
    Logger.warning(
      "Restarting HomeKit bridge after pair setup remained at step #{inspect(step)} for #{elapsed_ms}ms"
    )

    state
    |> stop_hap()
    |> rebuild()
  end

  defp notify_change_token(nil), do: :ok

  defp notify_change_token(token) do
    _ = HAP.value_changed(token)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp token_key(opts) do
    case {Keyword.get(opts, :kind), Keyword.get(opts, :id)} do
      {kind, id} when kind in [:light, :group] and is_integer(id) ->
        {:entity, kind, id, Keyword.get(opts, :characteristic, :on)}

      {:scene, id} when is_integer(id) ->
        {:scene, id}

      _ ->
        {:unknown, opts}
    end
  end

  defp hap_module do
    Application.get_env(:hueworks, :homekit_hap_module, Hueworks.HomeKit.HAP)
  end

  defp pair_setup_step do
    module = Application.get_env(:hueworks, :homekit_pair_setup_module, HAP.PairSetup)

    state =
      if function_exported?(module, :state, 0) do
        module.state()
      else
        :sys.get_state(module)
      end

    case state do
      %{step: step} -> {:ok, step}
      _ -> {:error, {:unexpected_pair_setup_state, state}}
    end
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp schedule_pairing_watchdog do
    Process.send_after(self(), :pairing_watchdog, pairing_watchdog_interval_ms())
  end

  defp pairing_timeout_ms do
    Application.get_env(:hueworks, :homekit_pairing_timeout_ms, @default_pairing_timeout_ms)
  end

  defp pairing_watchdog_interval_ms do
    Application.get_env(
      :hueworks,
      :homekit_pairing_watchdog_interval_ms,
      @default_pairing_watchdog_interval_ms
    )
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp maybe_cast(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      _ -> :ok
    end
  end
end
