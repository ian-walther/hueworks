defmodule Hueworks.Control.CircadianPoller do
  @moduledoc """
  Periodically reapplies active scenes for circadian adjustments.
  """

  use GenServer
  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.TransitionPolicy
  alias Hueworks.DebugLogging
  alias Hueworks.Scenes

  @default_interval_ms 60_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, poll_interval_ms())
    now_fn = Keyword.get(opts, :now_fn, &DateTime.utc_now/0)
    {:ok, %{interval: interval, now_fn: now_fn}, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state) do
    run_tick(state.now_fn.())
    schedule_tick(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    run_tick(state.now_fn.())
    schedule_tick(state)
    {:noreply, state}
  end

  def run_tick(now \\ DateTime.utc_now()) when is_struct(now, DateTime) do
    active_scenes = ActiveScenes.list_active_scenes()
    started_at_ms = System.monotonic_time(:millisecond)

    DebugLogging.info("circadian_tick_start active_scene_count=#{length(active_scenes)}")

    {applied, failed} =
      Enum.reduce(active_scenes, {0, 0}, fn active, {applied, failed} ->
        case Scenes.get_scene(active.scene_id) do
          nil ->
            Logger.warning(
              "circadian_scene_apply result=missing_scene area_id=#{active.area_id} scene_id=#{active.scene_id}"
            )

            {applied, failed + 1}

          scene ->
            trace = %{
              trace_id: "circadian-#{active.area_id}-#{System.unique_integer([:positive])}",
              source: "circadian_poller.tick",
              started_at_ms: System.monotonic_time(:millisecond)
            }

            case apply_active_scene(scene, active, now, trace) do
              {:ok, diff, _updated} ->
                DebugLogging.info(
                  "circadian_scene_apply result=ok area_id=#{scene.area_id} scene_id=#{scene.id} diff_size=#{map_size(diff)}"
                )

                {applied + 1, failed}

              {:error, reason} ->
                Logger.warning(
                  "circadian_scene_apply result=error area_id=#{scene.area_id} scene_id=#{scene.id} reason=#{inspect(reason)}"
                )

                {applied, failed + 1}

              other ->
                Logger.warning(
                  "circadian_scene_apply result=unexpected area_id=#{scene.area_id} scene_id=#{scene.id} value=#{inspect(other)}"
                )

                {applied, failed + 1}
            end
        end
      end)

    DebugLogging.info(
      "circadian_tick_end active_scene_count=#{length(active_scenes)} applied=#{applied} failed=#{failed} elapsed_ms=#{System.monotonic_time(:millisecond) - started_at_ms}"
    )
  end

  defp apply_active_scene(scene, active_scene, now, trace) do
    cond do
      ActiveScenes.circadian_deferred?(active_scene, now) and
          Scenes.active_scene_rehydrate_needed?(scene.id) ->
        remaining_ms = ActiveScenes.remaining_circadian_deferral_ms(active_scene, now)

        Scenes.apply_active_scene(scene, active_scene,
          preserve_power_latches: true,
          origin: :scene_activation,
          transition_policy: TransitionPolicy.new(remaining_ms, :none),
          now: now,
          trace: trace
        )

      ActiveScenes.circadian_deferred?(active_scene, now) ->
        {:ok, %{}, %{}}

      true ->
        Scenes.apply_active_scene(scene, active_scene,
          preserve_power_latches: true,
          origin: :circadian,
          now: now,
          trace: trace
        )
    end
  end

  defp schedule_tick(state) do
    Process.send_after(self(), :tick, state.interval)
  end

  defp poll_interval_ms do
    Application.get_env(:hueworks, :circadian_poll_interval_ms, @default_interval_ms)
  end
end
