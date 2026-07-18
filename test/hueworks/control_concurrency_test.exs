defmodule Hueworks.ControlConcurrencyTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{Apply, DesiredState, Executor, State}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, Area}

  setup do
    actions_id = {:control_concurrency_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, &(&1 ++ [action]))
      :ok
    end

    server = {:global, {:control_concurrency_executor, self()}}

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: server, dispatch_fun: dispatch_fun, bridge_rate_fun: fn _ -> 10 end, max_retries: 0}
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

  test "stale group recovery preserves its sibling without double-dispatching the newer light", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    bridge =
      insert_bridge!(%{
        name: "Grouped Shared Bridge",
        type: :hue,
        host: "192.168.1.211",
        credentials: %{"api_key" => "test"}
      })

    area = Repo.insert!(%Area{name: "Grouped Concurrency Area"})
    light_a = insert_light!(bridge.id, area.id, "grouped-a")
    light_b = insert_light!(bridge.id, area.id, "grouped-b")

    group =
      Repo.insert!(%Group{
        name: "Shared Group",
        display_name: "Shared Group",
        source: :hue,
        source_id: "shared-group",
        bridge_id: bridge.id,
        area_id: area.id
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    Enum.each([light_a, light_b], fn light ->
      _ = DesiredState.put(:light, light.id, %{power: :off})
      _ = State.put(:light, light.id, %{power: :off})
    end)

    old_group_txn =
      :circadian_tick
      |> DesiredState.begin()
      |> DesiredState.apply(:light, light_a.id, %{power: :on, brightness: 25, kelvin: 2400})
      |> DesiredState.apply(:light, light_b.id, %{power: :on, brightness: 25, kelvin: 2400})

    assert {:ok, %{plan_diff: old_diff}} =
             Apply.commit_transaction(old_group_txn, force_apply: true)

    [stale_group_action] = deferred_plan(area.id, old_diff)
    assert stale_group_action.type == :group

    newer_light_txn =
      :manual_control
      |> DesiredState.begin()
      |> DesiredState.apply(:light, light_a.id, %{power: :on, brightness: 85, kelvin: 4000})

    assert {:ok, %{plan_diff: newer_diff}} =
             Apply.commit_transaction(newer_light_txn, force_apply: true)

    assert :ok = Apply.enqueue_plan(deferred_plan(area.id, newer_diff))
    assert :ok = Apply.enqueue_plan([stale_group_action])

    Enum.each(1..3, fn _ -> Executor.tick(executor_server, force: true) end)

    actions = Agent.get(actions_agent, & &1)

    assert Enum.map(actions, & &1.id) |> Enum.frequencies() == %{
             light_a.id => 1,
             light_b.id => 1
           }

    assert Enum.all?(actions, fn action ->
             action.desired == DesiredState.get(:light, action.id)
           end)
  end

  test "newest scene intent survives delayed manual and circadian plans on one bridge", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    bridge =
      insert_bridge!(%{
        name: "Shared Bridge",
        type: :hue,
        host: "192.168.1.210",
        credentials: %{"api_key" => "test"}
      })

    area = Repo.insert!(%Area{name: "Concurrency Area"})

    light =
      Repo.insert!(%Light{
        name: "Shared Lamp",
        display_name: "Shared Lamp",
        source: :hue,
        source_id: "shared-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    circadian_plan = staged_plan(area.id, light.id, :circadian_tick, 25, 2400)
    manual_plan = staged_plan(area.id, light.id, :manual_control, 55, 3000)
    scene_plan = staged_plan(area.id, light.id, :scene_activation, 85, 4000)

    assert :ok = Apply.enqueue_plan(scene_plan)
    assert :ok = Apply.enqueue_plan(manual_plan)
    assert :ok = Apply.enqueue_plan(circadian_plan)

    assert DesiredState.get(:light, light.id) == %{
             power: :on,
             brightness: 85,
             kelvin: 4000
           }

    _ = Executor.tick(executor_server, force: true)
    _ = Executor.tick(executor_server, force: true)

    assert [action] = Agent.get(actions_agent, & &1)
    assert action.id == light.id
    assert action.desired == DesiredState.get(:light, light.id)
    assert action.attempts == 0
  end

  defp staged_plan(area_id, light_id, source, brightness, kelvin) do
    txn =
      source
      |> DesiredState.begin()
      |> DesiredState.apply(:light, light_id, %{
        power: :on,
        brightness: brightness,
        kelvin: kelvin
      })

    assert {:ok, %{plan_diff: diff}} = Apply.commit_transaction(txn, force_apply: true)

    area_id
    |> deferred_plan(diff)
  end

  defp deferred_plan(area_id, diff) do
    area_id
    |> Apply.build_plan(diff)
    |> Enum.map(&Map.put(&1, :not_before, System.monotonic_time(:millisecond) + 60_000))
  end

  defp insert_light!(bridge_id, area_id, source_id) do
    Repo.insert!(%Light{
      name: source_id,
      display_name: source_id,
      source: :hue,
      source_id: source_id,
      bridge_id: bridge_id,
      area_id: area_id,
      supports_temp: true,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6500
    })
  end
end
