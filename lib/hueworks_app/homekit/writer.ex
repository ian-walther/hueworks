defmodule Hueworks.HomeKit.Writer do
  @moduledoc """
  Applies HomeKit characteristic writes off the HAP request path.

  HAP answers a write as soon as it is accepted here, so the HomeKit session never waits
  on the planner, the executor, or a bridge round trip. Writes for one entity are buffered
  for a short window so the On and Brightness values the Home app sends together become a
  single desired-state transaction instead of a power-on at baseline followed by a dim.

  Each apply runs in its own supervised task, so a slow or crashed apply (for example an
  executor call timing out behind a stalled bridge) cannot take down this process or the
  other writes it has already accepted.

  Ordering: every write belongs to an area, and everything in an area shares state (the
  active scene, its power-override map, overlapping groups), so applies within one area
  run one at a time in acceptance order while different areas run concurrently. A write
  only merges into an earlier pending write for the same entity if nothing for that area
  was accepted in between; an intervening write is a coalescing boundary, so an older
  power instruction can never be carried past a newer command just because a later
  brightness write shares its accessory.
  """

  use GenServer
  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.Color
  alias Hueworks.Control.{DesiredState, ManualBaseline, State}
  alias Hueworks.DebugLogging
  alias Hueworks.HomeKit.{ValueCache, ValueStore}
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Scenes

  @default_coalesce_ms 25
  @task_supervisor Hueworks.HomeKit.TaskSupervisor

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def task_supervisor, do: @task_supervisor

  def submit(%{kind: kind, id: id, area_id: area_id} = target, characteristic, value, generation)
      when kind in [:light, :group] and
             characteristic in [:on, :brightness, :hue, :saturation, :color_temperature] and
             is_integer(generation) do
    GenServer.cast(
      __MODULE__,
      {:submit, {kind, id}, area_id, target, characteristic, value, generation, now_ms()}
    )
  end

  def submit_scene(%{id: scene_id, area_id: area_id}, active?, generation)
      when is_integer(scene_id) and is_boolean(active?) and is_integer(generation) do
    GenServer.cast(
      __MODULE__,
      {:submit, {:scene, scene_id}, area_id, scene_id, :on, active?, generation, now_ms()}
    )
  end

  @doc "Applies every buffered write now and returns once all in-flight applies finish."
  def flush do
    GenServer.call(__MODULE__, :flush, 15_000)
  end

  @doc "Drops buffered writes and stops in-flight applies. Intended for tests."
  def discard_pending do
    GenServer.call(__MODULE__, :discard_pending)
  end

  # pending: entries in acceptance order; in_flight: task ref => %{pid, entry}
  @impl true
  def init(_state), do: {:ok, %{pending: [], in_flight: %{}, flush_waiters: []}}

  @impl true
  def handle_cast(
        {:submit, key, area_id, target, characteristic, value, generation, submitted_at_ms},
        state
      ) do
    pending =
      case mergeable_index(state.pending, key, area_id) do
        nil ->
          state.pending ++ [new_entry(key, area_id, target, submitted_at_ms)]

        index ->
          List.update_at(state.pending, index, &%{&1 | target: target})
      end

    index = mergeable_index(pending, key, area_id)

    pending =
      List.update_at(pending, index, fn entry ->
        entry
        |> cancel_conflicting_color(characteristic)
        |> Map.update!(:attrs, &Map.put(&1, characteristic, value))
        |> Map.update!(:generations, &Map.put(&1, characteristic, generation))
      end)

    {:noreply, %{state | pending: pending}}
  end

  # Home Assistant's rule: a color temperature write cancels a pending hue/saturation and
  # a hue or saturation write cancels a pending color temperature. Their cache entries
  # were already superseded when the new write was accepted.
  defp cancel_conflicting_color(entry, characteristic) do
    cancelled =
      case characteristic do
        :color_temperature -> [:hue, :saturation]
        c when c in [:hue, :saturation] -> [:color_temperature]
        _ -> []
      end

    %{
      entry
      | attrs: Map.drop(entry.attrs, cancelled),
        generations: Map.drop(entry.generations, cancelled)
    }
  end

  @impl true
  def handle_call(:flush, from, state) do
    state =
      state.pending
      |> Enum.map(& &1.id)
      |> Enum.reduce(state, &mark_ready(&2, &1))
      |> dispatch_ready()

    if idle?(state) do
      {:reply, :ok, state}
    else
      {:noreply, %{state | flush_waiters: [from | state.flush_waiters]}}
    end
  end

  def handle_call(:discard_pending, _from, state) do
    Enum.each(state.pending, &cancel_timer/1)

    Enum.each(state.in_flight, fn {_ref, %{pid: pid}} ->
      Task.Supervisor.terminate_child(@task_supervisor, pid)
    end)

    {:reply, :ok, %{state | pending: [], in_flight: %{}}}
  end

  @impl true
  def handle_info({:ready, id}, state) do
    {:noreply, state |> mark_ready(id) |> dispatch_ready()}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish(state, ref)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.get(state.in_flight, ref) do
      %{entry: %{key: {kind, id}} = entry} ->
        Logger.warning("HomeKit #{kind} write crashed: #{inspect(reason)}")
        ValueCache.invalidate(kind, id, entry.generations)

      nil ->
        :ok
    end

    {:noreply, finish(state, ref)}
  end

  defp new_entry(key, area_id, target, submitted_at_ms) do
    id = System.unique_integer([:positive, :monotonic])

    %{
      id: id,
      key: key,
      area_id: area_id,
      target: target,
      attrs: %{},
      generations: %{},
      submitted_at_ms: submitted_at_ms,
      timer: Process.send_after(self(), {:ready, id}, coalesce_ms()),
      ready?: false
    }
  end

  # The most recent pending entry for `key` can absorb a new write only if nothing for
  # the same area was accepted after it.
  defp mergeable_index(pending, key, area_id) do
    pending
    |> Enum.with_index()
    |> Enum.filter(fn {entry, _index} -> entry.key == key end)
    |> List.last()
    |> case do
      nil ->
        nil

      {_entry, index} ->
        boundary? = pending |> Enum.drop(index + 1) |> Enum.any?(&(&1.area_id == area_id))
        if boundary?, do: nil, else: index
    end
  end

  defp mark_ready(state, id) do
    pending =
      Enum.map(state.pending, fn
        %{id: ^id} = entry ->
          cancel_timer(entry)
          %{entry | ready?: true, timer: nil}

        entry ->
          entry
      end)

    %{state | pending: pending}
  end

  # Walks pending in acceptance order. A ready entry starts unless its area is busy: an
  # in-flight apply, or an earlier pending entry (ready or not) for the same area.
  defp dispatch_ready(state) do
    busy = state.in_flight |> Map.values() |> Enum.map(& &1.entry.area_id)

    {state, _busy, remaining} =
      Enum.reduce(state.pending, {state, busy, []}, fn entry, {acc, busy, remaining} ->
        if entry.ready? and entry.area_id not in busy do
          {start_apply(acc, entry), [entry.area_id | busy], remaining}
        else
          {acc, [entry.area_id | busy], [entry | remaining]}
        end
      end)

    %{state | pending: Enum.reverse(remaining)}
  end

  defp start_apply(state, entry) do
    task = Task.Supervisor.async_nolink(@task_supervisor, fn -> apply_entry(entry) end)
    %{state | in_flight: Map.put(state.in_flight, task.ref, %{pid: task.pid, entry: entry})}
  end

  defp finish(state, ref) do
    %{state | in_flight: Map.delete(state.in_flight, ref)}
    |> dispatch_ready()
    |> reply_flush_waiters()
  end

  defp reply_flush_waiters(state) do
    if idle?(state) do
      Enum.each(state.flush_waiters, &GenServer.reply(&1, :ok))
      %{state | flush_waiters: []}
    else
      state
    end
  end

  defp idle?(state), do: state.in_flight == %{} and state.pending == []

  defp cancel_timer(%{timer: nil}), do: :ok
  defp cancel_timer(%{timer: timer}), do: Process.cancel_timer(timer)

  # Runs inside a supervised task.
  defp apply_entry(%{key: {:scene, scene_id}, attrs: %{on: active?}} = entry) do
    started_ms = now_ms()

    result =
      if active? do
        Scenes.activate_scene(scene_id, trace: %{source: :homekit})
      else
        ActiveScenes.deactivate_scene(scene_id)
        {:ok, :deactivated}
      end

    log_applied(entry.key, entry.attrs, entry.submitted_at_ms, started_ms, result)

    case result do
      {:error, reason} -> Logger.warning("HomeKit scene write failed: #{inspect(reason)}")
      _ -> :ok
    end

    # Active-scene state lives in the database, so it is authoritative as soon as the
    # activation returns. Only this write's entry is dropped; a newer one keeps masking.
    ValueCache.invalidate(:scene, scene_id, entry.generations)
    result
  end

  defp apply_entry(%{key: {kind, id}, target: target, attrs: attrs} = entry) do
    started_ms = now_ms()
    result = apply_attrs(target, attrs, entry.submitted_at_ms)
    log_applied(entry.key, attrs, entry.submitted_at_ms, started_ms, result)

    case result do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("HomeKit #{kind} write failed: #{inspect(reason)}")
        ValueCache.invalidate(kind, id, entry.generations)
    end

    result
  end

  defp apply_attrs(%{area_id: area_id, light_ids: light_ids} = target, attrs, submitted_at_ms) do
    trace = trace(target, submitted_at_ms)
    levels = level_desired(target, attrs)

    cond do
      # Brightness 0 is a power-off request, as in Home Assistant.
      attrs[:on] == false or attrs[:brightness] == 0 ->
        ManualControl.apply_power_action(area_id, light_ids, :off, trace: trace)

      attrs[:on] == true and levels == %{} ->
        ManualControl.apply_power_action(area_id, light_ids, :on, trace: trace)

      attrs[:on] == true ->
        if ActiveScenes.get_for_area(area_id) do
          # The active scene owns levels and color. They were refused when accepted unless
          # the scene became active since; either way only power applies.
          ManualControl.apply_power_action(area_id, light_ids, :on, trace: trace)
        else
          ManualControl.apply_updates(area_id, light_ids, power_on_desired(levels), trace: trace)
        end

      levels != %{} ->
        ManualControl.apply_updates(area_id, light_ids, levels, trace: trace)

      true ->
        {:ok, :noop}
    end
  end

  # Power on at the manual baseline, overridden by whatever HomeKit asked for. A color
  # write replaces the baseline temperature rather than sitting beside it.
  defp power_on_desired(levels) do
    base = ManualBaseline.power_on_state()
    base = if Map.has_key?(levels, :x), do: Map.delete(base, :kelvin), else: base
    Map.merge(base, levels)
  end

  # HomeKit levels mapped onto HueWorks desired-state attributes: brightness as is, mireds
  # to kelvin clamped to the entity's effective range, and hue/saturation to xy. When only
  # one of hue or saturation arrives, the other comes from committed intent.
  defp level_desired(target, attrs) do
    %{}
    |> maybe_put_brightness(attrs)
    |> maybe_put_kelvin(target, attrs)
    |> maybe_put_xy(target, attrs)
  end

  defp maybe_put_brightness(desired, %{brightness: brightness}) when is_number(brightness),
    do: Map.put(desired, :brightness, brightness)

  defp maybe_put_brightness(desired, _attrs), do: desired

  defp maybe_put_kelvin(desired, target, %{color_temperature: mireds}) when is_number(mireds) do
    kelvin = ValueStore.mireds_to_kelvin(mireds, target.min_kelvin, target.max_kelvin)
    Map.put(desired, :kelvin, kelvin)
  end

  defp maybe_put_kelvin(desired, _target, _attrs), do: desired

  defp maybe_put_xy(desired, target, attrs)
       when is_map_key(attrs, :hue) or is_map_key(attrs, :saturation) do
    {intent_hue, intent_saturation} = intent_hs(target)
    hue = Map.get(attrs, :hue, intent_hue)
    saturation = Map.get(attrs, :saturation, intent_saturation)

    case Color.hs_to_xy(hue, saturation) do
      {x, y} -> desired |> Map.put(:x, x) |> Map.put(:y, y)
      _ -> desired
    end
  end

  defp maybe_put_xy(desired, _target, _attrs), do: desired

  # The half of a partial color write HomeKit did not send comes from committed intent:
  # the desired state of the target's lights as the previous apply in this area's
  # sequence left it. Observed state is only a fallback for lights with no color intent.
  # The readback cache is never consulted here; it may already hold a later pending write.
  defp intent_hs(%{kind: kind, id: id, light_ids: light_ids}) do
    intent =
      Enum.find_value(light_ids, fn light_id ->
        ValueStore.color_hs(DesiredState.get(:light, light_id) || %{})
      end)

    intent || ValueStore.color_hs(State.get(kind, id) || %{}) || {0, 0}
  end

  defp trace(%{kind: kind, id: id, area_id: area_id}, submitted_at_ms) do
    %{
      trace_id: "homekit-#{kind}-#{id}-#{System.unique_integer([:positive])}",
      source: "homekit",
      area_id: area_id,
      started_at_ms: submitted_at_ms
    }
  end

  defp log_applied({kind, id}, attrs, submitted_at_ms, started_ms, result) do
    outcome =
      case result do
        {:error, reason} -> "error=#{inspect(reason)}"
        _ -> "result=ok"
      end

    DebugLogging.info(
      "[homekit] write_applied kind=#{kind} id=#{id} attrs=#{inspect(attrs)} coalesce_ms=#{started_ms - submitted_at_ms} apply_ms=#{now_ms() - started_ms} #{outcome}"
    )
  end

  defp coalesce_ms do
    Application.get_env(:hueworks, :homekit_write_coalesce_ms, @default_coalesce_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
