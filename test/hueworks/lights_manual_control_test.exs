defmodule Hueworks.LightsManualControlTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, Executor, State, TraceBuffer}
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, Area, Scene}

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
