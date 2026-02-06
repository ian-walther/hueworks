defmodule Hueworks.Control.CircadianPoller do
  @moduledoc """
  Periodically reapplies active scenes for circadian adjustments.
  """

  use GenServer

  alias Hueworks.ActiveScenes
  alias Hueworks.Scenes

  @default_interval_ms 60_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, poll_interval_ms())
    {:ok, %{interval: interval}, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state) do
    schedule_tick(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    run_tick()
    schedule_tick(state)
    {:noreply, state}
  end

  defp run_tick do
    ActiveScenes.list_active_scenes()
    |> Enum.each(fn active ->
      case Scenes.get_scene(active.scene_id) do
        nil ->
          :ok

        scene ->
          _ = Scenes.apply_scene(scene, brightness_override: active.brightness_override)
          _ = ActiveScenes.mark_applied(active)
      end
    end)
  end

  defp schedule_tick(state) do
    Process.send_after(self(), :tick, state.interval)
  end

  defp poll_interval_ms do
    Application.get_env(:hueworks, :circadian_poll_interval_ms, @default_interval_ms)
  end
end
