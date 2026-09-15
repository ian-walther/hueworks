defmodule Hueworks.HomeKit.Bridge do
  @moduledoc false

  use GenServer
  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.DomainEvents
  alias Hueworks.HomeKit.{AccessoryGraph, ValueCache, ValueStore}
  alias Phoenix.PubSub

  @control_topic "control_state"
  @idle_pair_setup_step 1
  @default_pairing_timeout_ms 30_000
  @default_pairing_watchdog_interval_ms 5_000
  @default_publish_after_pairing_delay_ms 10_000
  @default_notify_debounce_ms 100
  @cache_expiry_margin_ms 25
  @never_notified :never_notified

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
    PubSub.subscribe(Hueworks.PubSub, DomainEvents.topic())
    PubSub.subscribe(Hueworks.PubSub, ValueCache.topic())
    schedule_pairing_watchdog()

    {:ok,
     %{
       hap_pid: nil,
       topology_hash: nil,
       change_tokens: %{},
       pairing_busy_since_ms: nil,
       pairing_shell?: false,
       publish_after_pairing_ref: nil,
       last_notified: %{},
       notify_timers: %{}
     }, {:continue, :reload}}
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
    state =
      state
      |> put_in([:change_tokens, key], change_token)
      |> remember_current_value(key)

    {:noreply, state}
  end

  @impl true
  def handle_info({:control_state, kind, id, control_state}, state)
      when kind in [:light, :group] and is_integer(id) do
    ValueCache.reconcile(kind, id, control_state)
    {:noreply, schedule_notify(state, {:entity, kind, id})}
  end

  def handle_info({:active_scene_updated, _area_id, _scene_id}, state) do
    ValueCache.clear_kind(:scene)
    {:noreply, schedule_notify(state, :scenes)}
  end

  def handle_info({:notify, group}, state) do
    state = %{state | notify_timers: Map.delete(state.notify_timers, group)}
    {:noreply, notify_group(state, group)}
  end

  # The controller that wrote `value` now believes it, whatever the cache holds by the
  # time this arrives (a fast failure may already have cleared it). Record that belief,
  # then push the current readable value at once so other controllers learn the write
  # and a value that already differs is corrected without waiting on the debounce. The
  # cached value masks observed state until it expires; re-read once it has, so the
  # writer learns what the bridge actually settled on, even when the device never moved.
  def handle_info({:homekit_value_written, kind, id, characteristic, value, ttl_ms}, state) do
    key = written_key(kind, id, characteristic)

    Process.send_after(
      self(),
      {:notify_expiry, cache_group(kind, id)},
      ttl_ms + @cache_expiry_margin_ms
    )

    state = %{state | last_notified: Map.put(state.last_notified, key, value)}
    {:noreply, notify_now(state, key)}
  end

  def handle_info({:homekit_value_cleared, kind, id}, state) do
    {:noreply, schedule_notify(state, cache_group(kind, id))}
  end

  def handle_info({:notify_expiry, group}, state) do
    {:noreply, notify_group(state, group)}
  end

  def handle_info({event, _scene}, state) when event in [:scene_saved, :scene_deleted] do
    {:noreply, rebuild(state)}
  end

  def handle_info(:pairing_watchdog, state) do
    schedule_pairing_watchdog()

    state =
      state
      |> maybe_restart_stuck_pairing()
      |> maybe_schedule_publish_after_pairing()

    {:noreply, state}
  end

  def handle_info(:publish_deferred_accessories, state) do
    {:noreply, %{state | publish_after_pairing_ref: nil} |> rebuild()}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp rebuild(state) do
    case AccessoryGraph.build() do
      {:disabled, _topology} ->
        state
        |> stop_hap()
        |> reset_notifications()
        |> Map.merge(%{
          topology_hash: nil,
          change_tokens: %{},
          pairing_busy_since_ms: nil,
          pairing_shell?: false
        })

      {:ok, accessory_server, topology} ->
        full_hash = AccessoryGraph.topology_hash(topology)

        {accessory_server, hash, pairing_shell?} =
          maybe_pairing_shell(accessory_server, full_hash)

        if hash == state.topology_hash and is_pid(state.hap_pid) do
          %{state | pairing_shell?: pairing_shell?}
        else
          state
          |> stop_hap()
          |> start_hap(accessory_server, hash, pairing_shell?)
        end
    end
  end

  defp maybe_pairing_shell(%{accessories: []} = accessory_server, full_hash) do
    {accessory_server, full_hash, false}
  end

  # Until pairing completes only the bridge accessory itself is published, so Apple Home's
  # add flow does not prompt for child names; children follow shortly after.
  defp maybe_pairing_shell(accessory_server, full_hash) do
    if pairing_state_module().paired?(accessory_server.data_path) do
      {accessory_server, full_hash, false}
    else
      {AccessoryGraph.pairing_shell(accessory_server), "pairing-shell:#{full_hash}", true}
    end
  end

  defp start_hap(state, accessory_server, topology_hash, pairing_shell?) do
    start_result =
      case hap_module().start_link(accessory_server) do
        {:ok, pid} ->
          Logger.info(
            "Started HomeKit bridge with #{length(accessory_server.accessories)} accessories"
          )

          {:ok, pid}

        {:error, {:already_started, pid}} ->
          {:ok, pid}

        other ->
          other
      end

    state = reset_notifications(state)

    case start_result do
      {:ok, pid} ->
        %{
          state
          | hap_pid: pid,
            topology_hash: topology_hash,
            change_tokens: %{},
            pairing_busy_since_ms: nil,
            pairing_shell?: pairing_shell?
        }

      {:error, reason} ->
        Logger.warning("Unable to start HomeKit bridge: #{inspect(reason)}")

        %{
          state
          | hap_pid: nil,
            topology_hash: nil,
            change_tokens: %{},
            pairing_busy_since_ms: nil,
            pairing_shell?: false
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

  defp maybe_schedule_publish_after_pairing(
         %{pairing_shell?: true, publish_after_pairing_ref: nil} = state
       ) do
    if pairing_state_module().paired?(current_data_path()) do
      Logger.info(
        "HomeKit pairing completed; publishing deferred accessories in #{publish_after_pairing_delay_ms()}ms"
      )

      ref =
        Process.send_after(
          self(),
          :publish_deferred_accessories,
          publish_after_pairing_delay_ms()
        )

      %{state | publish_after_pairing_ref: ref}
    else
      state
    end
  end

  defp maybe_schedule_publish_after_pairing(state), do: state

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

  # Notifications are debounced per entity and only sent when the value HomeKit would
  # read has actually changed. That collapses the burst of control-state broadcasts a
  # group re-derivation produces, and stops HomeKit's own writes echoing back to it with
  # a stale value.
  defp schedule_notify(state, group) do
    if Map.has_key?(state.notify_timers, group) do
      state
    else
      ref = Process.send_after(self(), {:notify, group}, notify_debounce_ms())
      %{state | notify_timers: Map.put(state.notify_timers, group, ref)}
    end
  end

  defp notify_group(state, group) do
    state.change_tokens
    |> Enum.filter(fn {key, _token} -> token_in_group?(key, group) end)
    |> Enum.reduce(state, fn {key, token}, acc -> notify_if_changed(acc, key, token) end)
  end

  defp notify_if_changed(state, key, token) do
    with {:ok, value} <- current_value(key),
         true <- Map.get(state.last_notified, key, @never_notified) != value do
      notify_change_token(token)
      %{state | last_notified: Map.put(state.last_notified, key, value)}
    else
      _ -> state
    end
  end

  defp cache_group(:scene, _id), do: :scenes
  defp cache_group(kind, id), do: {:entity, kind, id}

  defp written_key(:scene, id, _characteristic), do: {:scene, id}
  defp written_key(kind, id, characteristic), do: {:entity, kind, id, characteristic}

  # Pushes the current value for `key` regardless of what was last notified.
  defp notify_now(state, key) do
    with token when not is_nil(token) <- Map.get(state.change_tokens, key),
         {:ok, value} <- current_value(key) do
      notify_change_token(token)
      %{state | last_notified: Map.put(state.last_notified, key, value)}
    else
      _ -> state
    end
  end

  defp token_in_group?({:entity, kind, id, _characteristic}, {:entity, kind, id}), do: true
  defp token_in_group?({:scene, _scene_id}, :scenes), do: true
  defp token_in_group?(_key, _group), do: false

  defp remember_current_value(state, key) do
    case current_value(key) do
      {:ok, value} -> %{state | last_notified: Map.put(state.last_notified, key, value)}
      _ -> state
    end
  end

  defp current_value(key) do
    case token_opts(key) do
      nil -> :error
      opts -> ValueStore.get_value(opts)
    end
  end

  defp token_opts({:entity, kind, id, characteristic}),
    do: [kind: kind, id: id, characteristic: characteristic]

  defp token_opts({:scene, id}), do: [kind: :scene, id: id]
  defp token_opts(_key), do: nil

  defp reset_notifications(state) do
    Enum.each(state.notify_timers, fn {_group, ref} -> Process.cancel_timer(ref) end)
    %{state | last_notified: %{}, notify_timers: %{}}
  end

  defp notify_change_token(nil), do: :ok

  defp notify_change_token(token) do
    _ = notifier_module().value_changed(token)
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

  defp notifier_module do
    Application.get_env(:hueworks, :homekit_notifier_module, HAP)
  end

  defp notify_debounce_ms do
    Application.get_env(:hueworks, :homekit_notify_debounce_ms, @default_notify_debounce_ms)
  end

  defp hap_module do
    Application.get_env(:hueworks, :homekit_hap_module, Hueworks.HomeKit.HAP)
  end

  defp pairing_state_module do
    Application.get_env(:hueworks, :homekit_pairing_state_module, Hueworks.HomeKit.PairingState)
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

  defp publish_after_pairing_delay_ms do
    Application.get_env(
      :hueworks,
      :homekit_publish_after_pairing_delay_ms,
      @default_publish_after_pairing_delay_ms
    )
  end

  defp current_data_path do
    Hueworks.AppSettings.get_global()
    |> Hueworks.HomeKit.Config.from_settings()
    |> Map.fetch!(:data_path)
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp maybe_cast(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      _ -> :ok
    end
  end
end
