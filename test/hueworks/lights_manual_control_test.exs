defmodule Hueworks.LightsManualControlTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, Executor, State}
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light, Room}

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
    original_delay = Application.get_env(:hueworks, :manual_control_reconcile_delay_ms)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)
    Application.put_env(:hueworks, :manual_control_reconcile_delay_ms, 25)

    on_exit(fn ->
      Application.put_env(:hueworks, :control_executor_enabled, original_enabled)
      Application.put_env(:hueworks, :control_executor_server, original_server)

      if is_nil(original_delay) do
        Application.delete_env(:hueworks, :manual_control_reconcile_delay_ms)
      else
        Application.put_env(:hueworks, :manual_control_reconcile_delay_ms, original_delay)
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
      Repo.insert!(%Bridge{
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
        enabled: true
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert {:ok, %{power: :on}} = ManualControl.apply_power_action(room.id, [light.id], :on)

    Process.sleep(60)
    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{type: :light, id: light_id, desired: %{power: :on}},
             %{type: :light, id: retry_light_id, desired: %{power: :on}}
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
      Repo.insert!(%Bridge{
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
        enabled: true
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert {:ok, %{power: :on}} = ManualControl.apply_power_action(room.id, [light.id], :on)
    _ = State.put(:light, light.id, %{power: :on})

    Process.sleep(60)
    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert [
             %{type: :light, id: light_id, desired: %{power: :on}}
           ] = actions

    assert light_id == light.id
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
end
