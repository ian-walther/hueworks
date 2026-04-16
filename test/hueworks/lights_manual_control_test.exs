defmodule Hueworks.LightsManualControlTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, Executor, State}
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, Room, Scene}

  setup do
    actions_id = {:executor_manual_control_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      :ok
    end

    server = {:global, {:executor_manual_control, self()}}

    {:ok, _pid} =
      start_supervised(
        {Executor, name: server, dispatch_fun: dispatch_fun, bridge_rate_fun: fn _ -> 10 end}
      )

    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)
    original_delays = Application.get_env(:hueworks, :manual_control_reconcile_delays_ms)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)
    Application.put_env(:hueworks, :manual_control_reconcile_delays_ms, [25])

    on_exit(fn ->
      Application.put_env(:hueworks, :control_executor_enabled, original_enabled)
      Application.put_env(:hueworks, :control_executor_server, original_server)

      if is_nil(original_delays) do
        Application.delete_env(:hueworks, :manual_control_reconcile_delays_ms)
      else
        Application.put_env(:hueworks, :manual_control_reconcile_delays_ms, original_delays)
      end
    end)

    {:ok, actions_agent: actions_agent, executor_server: server}
  end

  test "manual power action retries when physical state stays stale", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    room = Repo.insert!(%Room{name: "Kitchen"})

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
        room_id: room.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert {:ok, %{power: :on, brightness: 100, kelvin: 3000}} =
             ManualControl.apply_power_action(room.id, [light.id], :on)

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
    room = Repo.insert!(%Room{name: "Office"})

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
        room_id: room.id,
        enabled: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert {:ok, %{power: :on, brightness: 100, kelvin: 3000}} =
             ManualControl.apply_power_action(room.id, [light.id], :on)

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
    room = Repo.insert!(%Room{name: "Active Scene Room"})
    scene = Repo.insert!(%Scene{name: "Evening", room_id: room.id, metadata: %{}})
    {:ok, _} = Hueworks.ActiveScenes.set_active(scene)

    assert {:error, :scene_active_manual_adjustment_not_allowed} =
             ManualControl.apply_updates(room.id, [123], %{brightness: 40})
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
end
