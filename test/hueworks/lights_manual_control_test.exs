defmodule Hueworks.LightsManualControlTest do
  use Hueworks.DataCase, async: false

  import ExUnit.CaptureLog

  alias Hueworks.Control.{DesiredState, Executor, State, TraceBuffer}
  alias Hueworks.Control.ManualBaseline
  alias Hueworks.Lights.ManualControl
  alias Hueworks.{ActiveScenes, Repo, Scenes}
  alias Hueworks.Schemas.{Group, GroupLight, Light, Area, Scene}

  setup do
    TraceBuffer.clear()

    actions_id = {:executor_manual_control_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      :ok
    end

    server = {:global, {:executor_manual_control, self()}}

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: server,
         dispatch_fun: dispatch_fun,
         bridge_rate_fun: fn _ -> 10 end,
         settlement_floor_ms: 25}
      )

    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)
    original_delays = Application.get_env(:hueworks, :manual_control_reconcile_delays_ms)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)
    Application.put_env(:hueworks, :manual_control_reconcile_delays_ms, [25])

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_server, original_server)
      restore_app_env(:hueworks, :manual_control_reconcile_delays_ms, original_delays)
    end)

    {:ok, actions_agent: actions_agent, executor_server: server}
  end

  test "manual updates preserve a caller-provided trace through planning", %{
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Trace Office"})

    bridge =
      insert_bridge!(%{
        name: "Trace Hue Bridge",
        type: :hue,
        host: "192.168.1.199",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Trace Desk Lamp",
        source: :hue,
        source_id: "trace-desk-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 10})
    _ = State.put(:light, light.id, %{power: :on, brightness: 10})

    trace = %{
      trace_id: "api-manual-update-#{light.id}",
      source: "api.light_control",
      area_id: area.id,
      started_at_ms: System.monotonic_time(:millisecond)
    }

    assert {:ok, _diff} =
             ManualControl.apply_updates(area.id, [light.id], %{brightness: 55}, trace: trace)

    assert %{events: events} = TraceBuffer.recent(trace_id: trace.trace_id)
    assert Enum.any?(events, &(&1.stage == :planned and &1.source == "api.light_control"))

    drain_executor(executor_server)
  end

  test "manual power action retries when physical state stays stale", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.91",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Kitchen Accent",
        source: :hue,
        source_id: "kitchen-accent",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert {:ok, %{power: :on, brightness: 100, kelvin: 3000}} =
             ManualControl.apply_power_action(area.id, [light.id], :on)

    wait_for_action_count(actions_agent, 2)
    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{
               type: :light,
               id: light_id,
               desired: %{power: :on, brightness: 100, kelvin: 3000}
             },
             %{
               type: :light,
               id: retry_light_id,
               desired: %{power: :on, brightness: 100, kelvin: 3000}
             }
           ] = actions

    assert light_id == light.id
    assert retry_light_id == light.id
  end

  test "manual power action does not retry after physical state catches up", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Office"})

    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.92",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Office Lamp",
        source: :hue,
        source_id: "office-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert {:ok, %{power: :on, brightness: 100, kelvin: 3000}} =
             ManualControl.apply_power_action(area.id, [light.id], :on)

    _ = State.put(:light, light.id, %{power: :on, brightness: 100, kelvin: 3000})

    Process.sleep(120)
    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{
               type: :light,
               id: light_id,
               desired: %{power: :on, brightness: 100, kelvin: 3000}
             }
           ] = actions

    assert light_id == light.id
  end

  test "manual power action uses the exact target group instead of a larger hardware group", %{
    actions_agent: actions_agent
  } do
    area = Repo.insert!(%Area{name: "Targeted Bedroom"})

    bridge =
      insert_bridge!(%{
        name: "Targeted Hue Bridge",
        type: :hue,
        host: "192.168.1.95",
        credentials: %{"api_key" => "test"}
      })

    ceiling =
      Repo.insert!(%Light{
        name: "Ceiling",
        source: :hue,
        source_id: "targeted-ceiling",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    lamp =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :hue,
        source_id: "targeted-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    all_lights =
      Repo.insert!(%Group{
        name: "All Bedroom Lights",
        source: :hue,
        source_id: "targeted-all-lights",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    ceiling_lights =
      Repo.insert!(%Group{
        name: "Ceiling Lights",
        source: :hue,
        source_id: "targeted-ceiling-lights",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: all_lights.id, light_id: ceiling.id})
    Repo.insert!(%GroupLight{group_id: all_lights.id, light_id: lamp.id})
    Repo.insert!(%GroupLight{group_id: ceiling_lights.id, light_id: ceiling.id})

    {:ok, light_state} =
      Scenes.create_manual_light_state("Targeted On", %{
        "brightness" => "100",
        "temperature" => "4000"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Targeted Auto", area_id: area.id})

    {:ok, _scene} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "All",
          light_ids: [ceiling.id, lamp.id],
          light_state_id: to_string(light_state.id)
        }
      ])

    {:ok, _active_scene} = ActiveScenes.set_active(scene)

    desired = %{power: :on, brightness: 100, kelvin: 4000}

    for light <- [ceiling, lamp] do
      _ = DesiredState.put(:light, light.id, desired)
      _ = State.put(:light, light.id, %{power: :off, brightness: 100, kelvin: 4000})
    end

    assert {:ok, _updated} =
             ManualControl.apply_power_action(area.id, [ceiling.id], :on)

    wait_for_action_count(actions_agent, 1)

    assert [%{type: :group, id: group_id} | _] = Agent.get(actions_agent, & &1)
    assert group_id == ceiling_lights.id
  end

  test "newer manual on is dispatched while an older off command is still settling", %{
    actions_agent: actions_agent
  } do
    area = Repo.insert!(%Area{name: "Rapid Bedroom"})

    bridge =
      insert_bridge!(%{
        name: "Rapid Hue Bridge",
        type: :hue,
        host: "192.168.1.96",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Rapid Lamp",
        source: :hue,
        source_id: "rapid-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    on_state = %{power: :on, brightness: 100, kelvin: 3000}
    _ = DesiredState.put(:light, light.id, on_state)
    _ = State.put(:light, light.id, on_state)

    assert {:ok, %{power: :off}} =
             ManualControl.apply_power_action(area.id, [light.id], :off)

    wait_for_action_count(actions_agent, 1)

    assert {:ok, %{power: :on}} =
             ManualControl.apply_power_action(area.id, [light.id], :on)

    wait_for_action_count(actions_agent, 2)

    assert [
             %{desired: %{power: :off}},
             %{desired: %{power: :on}}
           ] = Agent.get(actions_agent, &Enum.take(&1, 2))
  end

  test "manual brightness changes are rejected while a scene is active" do
    area = Repo.insert!(%Area{name: "Active Scene Area"})
    scene = Repo.insert!(%Scene{name: "Evening", area_id: area.id, metadata: %{}})
    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    assert {:error, :scene_active_manual_adjustment_not_allowed} =
             ManualControl.apply_updates(area.id, [123], %{brightness: 40})
  end

  test "manual power updates remain eligible during circadian deferral" do
    area = Repo.insert!(%Area{name: "Deferred Manual Area"})

    bridge =
      insert_bridge!(%{
        name: "Deferred Manual Hue Bridge",
        type: :hue,
        host: "192.168.1.94",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Deferred Manual Lamp",
        source: :hue,
        source_id: "deferred-manual-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    scene = Repo.insert!(%Scene{name: "Deferred Evening", area_id: area.id, metadata: %{}})
    resume_at = DateTime.add(DateTime.utc_now(), 60, :second)
    {:ok, _} = Hueworks.ActiveScenes.set_active(scene, circadian_resume_at: resume_at)
    _ = DesiredState.put(:light, light.id, %{power: :on})

    assert {:ok, diff} = ManualControl.apply_updates(area.id, [light.id], %{power: :off})
    assert diff[{:light, light.id}] == %{power: :off}
    assert DesiredState.get(:light, light.id) == %{power: :off}
    assert Hueworks.ActiveScenes.get_for_area(area.id).circadian_resume_at == resume_at
  end

  test "manual updates preserve queued work for other areas on the same bridge", %{
    executor_server: executor_server
  } do
    queued_area = Repo.insert!(%Area{name: "Queued Area"})
    manual_area = Repo.insert!(%Area{name: "Manual Area"})

    bridge =
      insert_bridge!(%{
        name: "Shared Hue Bridge",
        type: :hue,
        host: "192.168.1.93",
        credentials: %{"api_key" => "test"}
      })

    queued_light =
      Repo.insert!(%Light{
        name: "Queued Lamp",
        source: :hue,
        source_id: "queued-lamp",
        bridge_id: bridge.id,
        area_id: queued_area.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    manual_light =
      Repo.insert!(%Light{
        name: "Manual Lamp",
        source: :hue,
        source_id: "manual-lamp",
        bridge_id: bridge.id,
        area_id: manual_area.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    queued_action = %{
      type: :light,
      id: queued_light.id,
      bridge_id: bridge.id,
      desired: %{power: :on},
      trace_area_id: queued_area.id,
      not_before: System.monotonic_time(:millisecond) + 60_000
    }

    assert :ok = Executor.enqueue([queued_action], server: executor_server, mode: :append)

    _ = DesiredState.put(:light, manual_light.id, %{power: :off})
    _ = State.put(:light, manual_light.id, %{power: :off})

    assert {:ok, _diff} =
             ManualControl.apply_updates(manual_area.id, [manual_light.id], %{power: :on})

    assert queued_targets(executor_server, bridge.id) |> Enum.member?({:light, queued_light.id})
  end

  describe "power results while a scene is active" do
    setup do
      area = Repo.insert!(%Area{name: "Main Floor"})

      bridge =
        insert_bridge!(%{
          name: "Results Hue Bridge",
          type: :hue,
          host: "192.168.1.95",
          credentials: %{"api_key" => "test"}
        })

      # A zero-width ramp fails the calculation on any date.
      {:ok, held} =
        Scenes.create_light_state("Unavailable", :circadian, %{
          "override_sunrise_timing" => true,
          "override_sunset_timing" => true,
          "sunrise_time" => "06:00:00",
          "sunset_time" => "18:00:00",
          "brightness_mode" => "linear",
          "brightness_mode_time_dark" => 0,
          "brightness_mode_time_light" => 0
        })

      {:ok, manual} =
        Scenes.create_manual_light_state("Bright", %{
          "brightness" => "80",
          "temperature" => "3000"
        })

      %{area: area, bridge: bridge, held: held, manual: manual}
    end

    defp insert_lamp(context, name) do
      Repo.insert!(%Light{
        name: name,
        source: :hue,
        source_id: name,
        bridge_id: context.bridge.id,
        area_id: context.area.id,
        enabled: true
      })
    end

    defp activate_scene(context, components) do
      {:ok, scene} = Scenes.create_scene(%{name: "Evening Auto", area_id: context.area.id})

      {:ok, _components} =
        Scenes.replace_scene_components(
          scene,
          Enum.map(components, fn {name, lights, light_state} ->
            %{
              name: name,
              light_ids: Enum.map(lights, & &1.id),
              light_state_id: to_string(light_state.id)
            }
          end)
        )

      {:ok, _active} = ActiveScenes.set_active(scene)
    end

    test "a held light reports nothing to display", context do
      lamp = insert_lamp(context, "held-lamp")
      activate_scene(context, [{"Held", [lamp], context.held}])
      DesiredState.put(:light, lamp.id, %{power: :off})

      capture_log(fn ->
        assert {:ok, %{}} == ManualControl.apply_power_action(context.area.id, [lamp.id], :on)
      end)

      assert DesiredState.get(:light, lamp.id) == %{power: :off}
    end

    test "a partly held selection does not lend one member's attrs to the others", context do
      held_lamp = insert_lamp(context, "held-lamp")
      manual_lamp = insert_lamp(context, "manual-lamp")

      activate_scene(context, [
        {"Held", [held_lamp], context.held},
        {"Manual", [manual_lamp], context.manual}
      ])

      DesiredState.put(:light, held_lamp.id, %{power: :off})
      DesiredState.put(:light, manual_lamp.id, %{power: :off})

      capture_log(fn ->
        assert {:ok, %{}} ==
                 ManualControl.apply_power_action(
                   context.area.id,
                   [held_lamp.id, manual_lamp.id],
                   :on
                 )
      end)

      assert DesiredState.get(:light, held_lamp.id) == %{power: :off}

      assert DesiredState.get(:light, manual_lamp.id) == %{
               power: :on,
               brightness: 80,
               kelvin: 3000
             }
    end

    test "a light outside the active scene reports nothing to display", context do
      in_scene = insert_lamp(context, "in-scene-lamp")
      outside = insert_lamp(context, "outside-lamp")
      activate_scene(context, [{"Manual", [in_scene], context.manual}])

      assert {:ok, %{}} == ManualControl.apply_power_action(context.area.id, [outside.id], :on)
    end

    test "an accepted on still reports the scene's attrs", context do
      lamp = insert_lamp(context, "manual-lamp")
      activate_scene(context, [{"Manual", [lamp], context.manual}])
      DesiredState.put(:light, lamp.id, %{power: :off})

      assert {:ok, %{power: :on, brightness: 80, kelvin: 3000}} ==
               ManualControl.apply_power_action(context.area.id, [lamp.id], :on)
    end

    test "an on that changes nothing still reports the scene's attrs", context do
      lamp = insert_lamp(context, "manual-lamp")
      activate_scene(context, [{"Manual", [lamp], context.manual}])
      DesiredState.put(:light, lamp.id, %{power: :on, brightness: 80, kelvin: 3000})

      assert {:ok, %{power: :on, brightness: 80, kelvin: 3000}} ==
               ManualControl.apply_power_action(context.area.id, [lamp.id], :on)
    end

    test "an accepted selection still reports merged attrs", context do
      first = insert_lamp(context, "first-lamp")
      second = insert_lamp(context, "second-lamp")
      activate_scene(context, [{"Manual", [first, second], context.manual}])

      assert {:ok, %{power: :on, brightness: 80, kelvin: 3000}} ==
               ManualControl.apply_power_action(context.area.id, [first.id, second.id], :on)
    end

    test "an off is still honored and reported during a failed calculation", context do
      lamp = insert_lamp(context, "held-lamp")
      activate_scene(context, [{"Held", [lamp], context.held}])
      DesiredState.put(:light, lamp.id, %{power: :on, brightness: 40, kelvin: 3000})

      capture_log(fn ->
        assert {:ok, %{power: :off}} ==
                 ManualControl.apply_power_action(context.area.id, [lamp.id], :off)
      end)

      assert DesiredState.get(:light, lamp.id) == %{power: :off}
    end
  end

  test "without an active scene power still reports the manual baseline" do
    area = Repo.insert!(%Area{name: "No Scene Area"})

    assert {:ok, ManualBaseline.power_on_state()} ==
             ManualControl.apply_power_action(area.id, [], :on)
  end

  defp drain_executor(server, attempts \\ 5)

  defp drain_executor(_server, 0), do: :ok

  defp drain_executor(server, attempts) do
    stats = Executor.stats(server)
    queues = Map.values(stats.queues)

    if Enum.all?(queues, &(&1 == 0)) do
      :ok
    else
      Executor.tick(server, force: true)
      drain_executor(server, attempts - 1)
    end
  end

  defp wait_for_action_count(actions_agent, expected_count, attempts \\ 20)

  defp wait_for_action_count(_actions_agent, _expected_count, 0), do: :ok

  defp wait_for_action_count(actions_agent, expected_count, attempts) do
    if Agent.get(actions_agent, &length/1) >= expected_count do
      :ok
    else
      Process.sleep(10)
      wait_for_action_count(actions_agent, expected_count, attempts - 1)
    end
  end

  defp queued_targets(server, bridge_id) do
    server
    |> :sys.get_state()
    |> Map.fetch!(:queues)
    |> Map.get(bridge_id, :queue.new())
    |> :queue.to_list()
    |> Enum.map(fn action -> {action.type, action.id} end)
  end
end
