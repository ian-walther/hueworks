defmodule Hueworks.ScenesQueueingTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Control.{Executor, State}
  alias Hueworks.Repo
  alias Hueworks.Scenes

  alias Hueworks.Schemas.{
    Group,
    GroupLight,
    Light,
    LightState,
    Room,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  setup do
    actions_id = {:executor_scene_queueing_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      State.put(action.type, action.id, action.desired)
      :ok
    end

    server = {:global, {:executor_scene_queueing, self()}}

    {:ok, _pid} =
      start_supervised(
        {Executor, name: server, dispatch_fun: dispatch_fun, bridge_rate_fun: fn _ -> 1 end}
      )

    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_server, original_server)
    end)

    {:ok, actions_agent: actions_agent, executor_server: server}
  end

  test "rapid same-bridge room activations dispatch both rooms", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.15",
        credentials: %{"api_key" => "test"}
      })

    room_one = Repo.insert!(%Room{name: "Bedroom"})
    room_two = Repo.insert!(%Room{name: "Hall"})

    light_one_a =
      Repo.insert!(%Light{
        name: "Bedroom Lamp A",
        display_name: "Bedroom Lamp A",
        source: :hue,
        source_id: "801",
        bridge_id: bridge.id,
        room_id: room_one.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_one_b =
      Repo.insert!(%Light{
        name: "Bedroom Lamp B",
        display_name: "Bedroom Lamp B",
        source: :hue,
        source_id: "803",
        bridge_id: bridge.id,
        room_id: room_one.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_two =
      Repo.insert!(%Light{
        name: "Hall Lamp",
        display_name: "Hall Lamp",
        source: :hue,
        source_id: "802",
        bridge_id: bridge.id,
        room_id: room_two.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group_one =
      Repo.insert!(%Group{
        name: "Bedroom Group A",
        display_name: "Bedroom Group A",
        source: :hue,
        source_id: "901",
        bridge_id: bridge.id,
        room_id: room_one.id
      })

    group_one_b =
      Repo.insert!(%Group{
        name: "Bedroom Group B",
        display_name: "Bedroom Group B",
        source: :hue,
        source_id: "903",
        bridge_id: bridge.id,
        room_id: room_one.id
      })

    group_two =
      Repo.insert!(%Group{
        name: "Hall Group",
        display_name: "Hall Group",
        source: :hue,
        source_id: "902",
        bridge_id: bridge.id,
        room_id: room_two.id
      })

    Repo.insert!(%GroupLight{group_id: group_one.id, light_id: light_one_a.id})
    Repo.insert!(%GroupLight{group_id: group_one_b.id, light_id: light_one_b.id})
    Repo.insert!(%GroupLight{group_id: group_two.id, light_id: light_two.id})

    bedroom_state_a =
      insert_light_state!(%{
        name: "Bedroom Warm A",
        type: :manual,
        config: %{"brightness" => "20", "temperature" => "2500"}
      })

    bedroom_state_b =
      insert_light_state!(%{
        name: "Bedroom Warm B",
        type: :manual,
        config: %{"brightness" => "35", "temperature" => "3000"}
      })

    hall_state =
      insert_light_state!(%{
        name: "Hall Warm",
        type: :manual,
        config: %{"brightness" => "30", "temperature" => "2700"}
      })

    bedroom_scene =
      Repo.insert!(%Scene{
        name: "Bedroom Bedtime",
        room_id: room_one.id,
        metadata: %{}
      })

    hall_scene =
      Repo.insert!(%Scene{
        name: "Hall Bedtime",
        room_id: room_two.id,
        metadata: %{}
      })

    bedroom_component_a =
      Repo.insert!(%SceneComponent{
        name: "Bedroom Component A",
        scene_id: bedroom_scene.id,
        light_state_id: bedroom_state_a.id,
        metadata: %{}
      })

    bedroom_component_b =
      Repo.insert!(%SceneComponent{
        name: "Bedroom Component B",
        scene_id: bedroom_scene.id,
        light_state_id: bedroom_state_b.id,
        metadata: %{}
      })

    hall_component =
      Repo.insert!(%SceneComponent{
        name: "Hall Component",
        scene_id: hall_scene.id,
        light_state_id: hall_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: bedroom_component_a.id,
      light_id: light_one_a.id
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: bedroom_component_b.id,
      light_id: light_one_b.id
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: hall_component.id,
      light_id: light_two.id
    })

    reset_states_for_lights([light_one_a.id, light_one_b.id, light_two.id])

    assert {:ok, _diff, _updated} = Scenes.activate_scene(bedroom_scene.id)
    assert {:ok, _diff, _updated} = Scenes.activate_scene(hall_scene.id)

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert Enum.map(actions, & &1.id) |> Enum.sort() ==
             Enum.sort([group_one.id, group_one_b.id, group_two.id])
  end

  test "active scene reapply does not starve a pending same-bridge sibling action", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.16",
        credentials: %{"api_key" => "test"}
      })

    room = Repo.insert!(%Room{name: "Circadian Queue Room"})

    light_one =
      Repo.insert!(%Light{
        name: "Circadian Lamp A",
        display_name: "Circadian Lamp A",
        source: :hue,
        source_id: "circadian-a",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_two =
      Repo.insert!(%Light{
        name: "Circadian Lamp B",
        display_name: "Circadian Lamp B",
        source: :hue,
        source_id: "circadian-b",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, circadian_state} =
      Scenes.create_light_state("Adaptive Queue", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 4000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 10_800,
        "brightness_mode_time_light" => 10_800
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Adaptive Queue Scene", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Adaptive",
          light_ids: [light_one.id, light_two.id],
          light_state_id: to_string(circadian_state.id)
        }
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York"
      })

    {:ok, active_scene} = ActiveScenes.set_active(scene)

    assert {:ok, _diff, _updated} =
             Scenes.apply_active_scene(scene, active_scene,
               now: ny_dt("2026-03-31 05:00:00"),
               occupied: true,
               preserve_power_latches: true
             )

    assert eventually_action_count(actions_agent, 1)
    [first_action] = Agent.get(actions_agent, & &1)
    first_id = first_action.id
    sibling_id = ([light_one.id, light_two.id] -- [first_id]) |> List.first()

    assert {:ok, _diff, _updated} =
             Scenes.apply_active_scene(scene, active_scene,
               now: ny_dt("2026-03-31 05:30:00"),
               occupied: true,
               preserve_power_latches: true
             )

    Executor.tick(executor_server, force: true)

    assert [_, second_action] = Agent.get(actions_agent, & &1)
    assert second_action.id == sibling_id
  end

  defp drain_executor(server, attempts \\ 5)

  defp drain_executor(_server, 0), do: :ok

  defp drain_executor(server, attempts) do
    server
    |> Executor.stats()
    |> Map.get(:queues)
    |> Map.values()
    |> Enum.all?(&(&1 == 0))
    |> case do
      true ->
        :ok

      false ->
        Executor.tick(server, force: true)
        drain_executor(server, attempts - 1)
    end
  end

  defp reset_states_for_lights(light_ids) do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      Enum.each(light_ids, fn id ->
        :ets.insert(:hueworks_control_state, {{:light, id}, %{power: :off}})
      end)
    end

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      Enum.each(light_ids, fn id ->
        :ets.delete(:hueworks_desired_state, {:light, id})
      end)
    end
  end

  defp insert_light_state!(attrs) do
    %LightState{}
    |> LightState.changeset(attrs)
    |> Repo.insert!()
  end

  defp eventually_action_count(actions_agent, expected_count, attempts \\ 20)
  defp eventually_action_count(_actions_agent, _expected_count, 0), do: false

  defp eventually_action_count(actions_agent, expected_count, attempts) do
    if Agent.get(actions_agent, &(length(&1) == expected_count)) do
      true
    else
      Process.sleep(10)
      eventually_action_count(actions_agent, expected_count, attempts - 1)
    end
  end

  defp ny_dt(local_time) do
    {:ok, naive} = NaiveDateTime.from_iso8601(local_time)
    DateTime.from_naive!(naive, "America/New_York") |> DateTime.shift_zone!("Etc/UTC")
  end
end
