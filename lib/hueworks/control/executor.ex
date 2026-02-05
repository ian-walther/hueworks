defmodule Hueworks.Control.Executor do
  @moduledoc """
  Executes control plans with per-bridge throttling.
  """

  use GenServer

  alias Hueworks.Control.{Group, Light}
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  @default_rates %{hue: 10, ha: 5, caseta: 5}
  @default_max_retries 3
  @default_backoff_ms 250

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def enqueue(actions, opts \\ []) when is_list(actions) do
    if enabled?() do
      server = Keyword.get(opts, :server, default_server())
      mode = Keyword.get(opts, :mode, :replace)
      GenServer.call(server, {:enqueue, actions, mode})
    else
      {:ok, :disabled}
    end
  end

  def stats(server \\ nil) do
    GenServer.call(server || default_server(), :stats)
  end

  def tick(server \\ nil, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    GenServer.call(server || default_server(), {:tick, force})
  end

  @doc false
  def commands_for_action(%{desired: desired}) when is_map(desired) do
    commands_for_desired(desired)
  end

  @impl true
  def init(opts) do
    dispatch_fun = Keyword.get(opts, :dispatch_fun, &default_dispatch/1)
    now_fn = Keyword.get(opts, :now_fn, &System.monotonic_time/1)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    backoff_ms = Keyword.get(opts, :backoff_ms, @default_backoff_ms)
    bridge_rate_fun = Keyword.get(opts, :bridge_rate_fun, &bridge_rate/1)

    {:ok,
     %{
       queues: %{},
       bridge_rates: %{},
       last_sent: %{},
       timer_ref: nil,
       dispatch_fun: dispatch_fun,
       now_fn: now_fn,
       max_retries: max_retries,
       backoff_ms: backoff_ms,
       bridge_rate_fun: bridge_rate_fun
     }}
  end

  @impl true
  def handle_call({:enqueue, actions, mode}, _from, state) do
    state = enqueue_actions(state, actions, mode)
    state = ensure_timer(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    queues =
      Enum.map(state.queues, fn {bridge_id, queue} ->
        {bridge_id, :queue.len(queue)}
      end)

    {:reply,
     %{
       queues: Map.new(queues),
       bridge_rates: state.bridge_rates,
       last_sent: state.last_sent
     }, state}
  end

  @impl true
  def handle_call({:tick, force}, _from, state) do
    {state, had_work, has_pending} = dispatch_tick(state, force)
    {:reply, %{had_work: had_work, has_pending: has_pending}, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {state, had_work, has_pending} = dispatch_tick(state)

    state =
      if had_work or has_pending do
        schedule_next(state)
      else
        %{state | timer_ref: nil}
      end

    {:noreply, state}
  end

  defp enabled? do
    Application.get_env(:hueworks, :control_executor_enabled, true)
  end

  defp default_server do
    Application.get_env(:hueworks, :control_executor_server, __MODULE__)
  end

  defp enqueue_actions(state, actions, mode) do
    actions_by_bridge = Enum.group_by(actions, & &1.bridge_id)

    Enum.reduce(actions_by_bridge, state, fn {bridge_id, bridge_actions}, acc ->
      now = acc.now_fn.(:millisecond)
      normalized = Enum.map(bridge_actions, &normalize_action(&1, now))
      
      existing_queue = Map.get(acc.queues, bridge_id, :queue.new())

      rate = Map.get(acc.bridge_rates, bridge_id) || acc.bridge_rate_fun.(bridge_id)
      interval = interval_ms(rate)

      queue =
        case mode do
          :append -> Enum.reduce(normalized, existing_queue, &:queue.in/2)
          _ -> Enum.reduce(normalized, :queue.new(), &:queue.in/2)
        end

      queues = Map.put(acc.queues, bridge_id, queue)
      bridge_rates = Map.put(acc.bridge_rates, bridge_id, rate)

      should_reset_last_sent =
        case mode do
          :append -> :queue.is_empty(existing_queue)
          _ -> true
        end

      last_sent =
        if should_reset_last_sent do
          Map.put(acc.last_sent, bridge_id, now - interval)
        else
          acc.last_sent
        end

      %{acc | queues: queues, bridge_rates: bridge_rates, last_sent: last_sent}
    end)
  end

  defp normalize_action(action, now) do
    action
    |> Map.put_new(:attempts, 0)
    |> Map.put_new(:not_before, now)
    |> Map.update(:attempts, 0, fn
      nil -> 0
      value -> value
    end)
    |> Map.update(:not_before, now, fn
      nil -> now
      value -> value
    end)
  end

  defp ensure_timer(%{timer_ref: nil} = state) do
    ref = Process.send_after(self(), :tick, 0)
    %{state | timer_ref: ref}
  end

  defp ensure_timer(state), do: state

  defp schedule_next(state) do
    delay =
      state.bridge_rates
      |> Enum.filter(fn {bridge_id, _rate} ->
        queue = Map.get(state.queues, bridge_id, :queue.new())
        not :queue.is_empty(queue)
      end)
      |> Enum.map(fn {_bridge_id, rate} -> interval_ms(rate) end)
      |> case do
        [] -> nil
        intervals -> Enum.min(intervals)
      end

    if is_integer(delay) do
      ref = Process.send_after(self(), :tick, delay)
      %{state | timer_ref: ref}
    else
      %{state | timer_ref: nil}
    end
  end

  defp dispatch_tick(state, force \\ false) do
    now = state.now_fn.(:millisecond)

    {queues, last_sent, had_work} =
      Enum.reduce(state.queues, {state.queues, state.last_sent, false}, fn {bridge_id, queue},
                                                                            {queues_acc, last_acc, worked} ->
        rate = Map.get(state.bridge_rates, bridge_id) || default_rate()
        interval = interval_ms(rate)
        last =
          case Map.get(last_acc, bridge_id) do
            nil -> now - interval
            0 -> now - interval
            value -> value
          end

        if :queue.is_empty(queue) or (not force and now - last < interval) do
          {queues_acc, last_acc, worked}
        else
          {action_result, updated_queue} =
            if force do
              case :queue.out(queue) do
                {:empty, _} -> {:none, queue}
                {{:value, action}, rest} -> {{:action, action}, rest}
              end
            else
              case next_action(queue, now) do
                {:none, rest} -> {:none, rest}
                {:action, action, rest} -> {{:action, action}, rest}
              end
            end

          case action_result do
            :none ->
              {Map.put(queues_acc, bridge_id, updated_queue), last_acc, worked}

            {:action, action} ->
              result = state.dispatch_fun.(action)

              {updated_queue, last_acc} =
                case result do
                  :ok ->
                    {updated_queue, Map.put(last_acc, bridge_id, now)}

                  {:error, _} ->
                    {requeue_action(updated_queue, action, now, state), last_acc}

                  _ ->
                    {updated_queue, Map.put(last_acc, bridge_id, now)}
                end

              queues_acc = Map.put(queues_acc, bridge_id, updated_queue)
              {queues_acc, last_acc, true}
          end
        end
      end)

    has_pending =
      queues
      |> Enum.any?(fn {_bridge_id, queue} -> not :queue.is_empty(queue) end)

    {%{state | queues: queues, last_sent: last_sent}, had_work, has_pending}
  end

  defp default_dispatch(action), do: dispatch_action(action)

  defp dispatch_action(%{type: :light, id: id, desired: desired}) do
    case Repo.get(Hueworks.Schemas.Light, id) do
      nil ->
        :ok

      light ->
        Light.set_state(light, desired)
    end
  end

  defp dispatch_action(%{type: :group, id: id, desired: desired}) do
    case Repo.get(Hueworks.Schemas.Group, id) do
      nil ->
        :ok

      group ->
        Group.set_state(group, desired)
    end
  end

  defp dispatch_action(_action), do: :ok

  defp commands_for_desired(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")

    case power do
      :off -> [:off]
      "off" -> [:off]
      _ -> build_on_commands(desired, power)
    end
  end

  defp build_on_commands(desired, power) do
    commands = if power in [:on, "on"], do: [:on], else: []
    brightness = value_or_nil(desired, [:brightness, "brightness"])
    kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])

    commands
    |> maybe_add(:brightness, brightness)
    |> maybe_add(:color_temp, kelvin)
  end

  defp maybe_add(commands, _key, nil), do: commands
  defp maybe_add(commands, key, value), do: commands ++ [{key, normalize_value(value)}]

  defp value_or_nil(desired, keys) do
    Enum.find_value(keys, fn key -> Map.get(desired, key) end)
  end

  defp normalize_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> value
    end
  end

  defp normalize_value(value), do: value

  defp next_action(queue, now) do
    case :queue.out(queue) do
      {:empty, _} ->
        {:none, queue}

      {{:value, action}, rest} ->
        not_before = action.not_before || now

        if not_before <= now do
          {:action, action, rest}
        else
          {:none, :queue.in_r(action, rest)}
        end
    end
  end

  defp requeue_action(queue, action, now, state) do
    if action.attempts + 1 > state.max_retries do
      queue
    else
      delay = state.backoff_ms * trunc(:math.pow(2, action.attempts))

      updated =
        action
        |> Map.update!(:attempts, &(&1 + 1))
        |> Map.put(:not_before, now + delay)

      :queue.in(updated, queue)
    end
  end

  defp bridge_rate(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil -> default_rate()
      %{type: type} -> Map.get(@default_rates, type, default_rate())
    end
  end

  defp default_rate, do: 5

  defp interval_ms(rate) when is_integer(rate) and rate > 0 do
    max(trunc(1000 / rate), 1)
  end

end
