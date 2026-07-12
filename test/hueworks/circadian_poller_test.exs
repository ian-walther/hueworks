defmodule Hueworks.CircadianPollerTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.{CircadianPoller, Executor}
  alias Hueworks.Repo
  alias Hueworks.Control.DesiredState
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{ActiveScene, Light, Room, Scene}

  defp insert_room do
    Repo.insert!(%Room{name: "Studio", metadata: %{}})
  end

  defp insert_scene(room) do
    Repo.insert!(%Scene{name: "Chill", room_id: room.id, metadata: %{}})
  end

  test "poller reapplies active scenes immediately on startup" do
    room = insert_room()
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    active = Repo.get_by!(ActiveScene, room_id: room.id)
    stale_last_applied_at = DateTime.add(DateTime.utc_now(), -5, :minute)

    active
    |> Ecto.Changeset.change(last_applied_at: stale_last_applied_at)
    |> Repo.update!()

    {:ok, pid} = CircadianPoller.start_link(name: nil, interval_ms: 60_000)

    assert eventually(fn ->
             refreshed = Repo.get_by!(ActiveScene, room_id: room.id)
             DateTime.compare(refreshed.last_applied_at, stale_last_applied_at) == :gt
           end)

    GenServer.stop(pid)
  end

  test "poller defers ordinary circadian reapplication until the active-scene deadline" do
    room = insert_room()
    scene = insert_scene(room)
    now = DateTime.add(DateTime.utc_now(), -60, :second)
    resume_at = DateTime.add(now, 30, :second)

    {:ok, _} = ActiveScenes.set_active(scene, now: now, circadian_resume_at: resume_at)
    before = Repo.get_by!(ActiveScene, room_id: room.id)

    assert :ok = CircadianPoller.run_tick(now)
    assert Repo.get_by!(ActiveScene, room_id: room.id).last_applied_at == before.last_applied_at

    assert :ok = CircadianPoller.run_tick(DateTime.add(resume_at, 1, :second))

    refreshed = Repo.get_by!(ActiveScene, room_id: room.id)
    assert DateTime.compare(refreshed.last_applied_at, before.last_applied_at) == :gt
  end

  test "an unexpired deferral rehydrates missing desired state without extending its deadline" do
    parent = self()
    executor_server = :circadian_rehydration_executor

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: executor_server,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         bridge_rate_fun: fn _ -> 20 end}
      )

    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)
    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, executor_server)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_server, original_server)
    end)

    room = insert_room()

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Poller Hue",
        host: "10.0.0.250",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Poller Lamp",
        source: :hue,
        source_id: "poller-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    {:ok, state} =
      Scenes.create_manual_light_state("Poller Manual", %{
        "brightness" => "40",
        "temperature" => "3000"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Poller Scene", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    now = DateTime.utc_now()
    resume_at = DateTime.add(now, 30, :second)
    {:ok, _} = ActiveScenes.set_active(scene, now: now, circadian_resume_at: resume_at)

    assert DesiredState.get(:light, light.id) == nil
    assert :ok = CircadianPoller.run_tick(DateTime.add(now, 10, :second))

    Executor.tick(executor_server, force: true)

    assert_receive {:dispatched,
                    %{
                      id: light_id,
                      apply_opts: %{transition_ms: 20_000},
                      operation: %{
                        origin: :scene_activation,
                        transition_policy: %{duration_ms: 20_000, scaling: :none}
                      }
                    }},
                   500

    assert light_id == light.id
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 40, kelvin: 3000}
    assert ActiveScenes.get_for_room(room.id).circadian_resume_at == resume_at
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
