defmodule Hueworks.Control.ExecutorConvergenceTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{
    DesiredState,
    DispatchReceipt,
    Executor,
    Operation,
    State,
    TransitionPolicy
  }

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, Area}

  setup do
    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_delay = Application.get_env(:hueworks, :control_executor_convergence_delay_ms)
    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_convergence_delay_ms, 10)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_convergence_delay_ms, original_delay)
    end)

    :ok
  end

  test "executor schedules recovery work when desired state still does not match physical state" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_convergence_retry,
         dispatch_fun: dispatch_fun,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 10}
      )

    area = Repo.insert!(%Area{name: "Convergence Retry Area"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.80",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Retry Lamp",
        source: :hue,
        source_id: "retry-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    light_id = light.id

    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [%{type: :light, id: light.id, bridge_id: bridge.id, desired: %{power: :on}}],
               server: :executor_convergence_retry,
               mode: :replace
             )

    Executor.tick(:executor_convergence_retry, force: true)
    assert_receive {:dispatched, %{id: ^light_id, attempts: 0}}, 500

    Process.sleep(30)
    Executor.tick(:executor_convergence_retry, force: true)
    assert_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 500
  end

  test "executor does not schedule recovery work once physical state catches up" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_convergence_ok,
         dispatch_fun: dispatch_fun,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 10}
      )

    area = Repo.insert!(%Area{name: "Convergence OK Area"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.81",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "OK Lamp",
        source: :hue,
        source_id: "ok-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    light_id = light.id

    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [%{type: :light, id: light.id, bridge_id: bridge.id, desired: %{power: :on}}],
               server: :executor_convergence_ok,
               mode: :replace
             )

    Executor.tick(:executor_convergence_ok, force: true)
    assert_receive {:dispatched, %{id: ^light_id, attempts: 0}}, 500

    _ = State.put(:light, light.id, %{power: :on})

    Process.sleep(30)
    Executor.tick(:executor_convergence_ok, force: true)
    refute_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 200
  end

  test "executor does not retry while a dispatched transition is still settling" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_transition_settlement,
         dispatch_fun: dispatch_fun,
         bridge_rate_fun: fn _ -> 20 end}
      )

    area = Repo.insert!(%Area{name: "Transition Settlement Area"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.82",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Settling Lamp",
        source: :hue,
        source_id: "settling-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [
                 %{
                   type: :light,
                   id: light.id,
                   bridge_id: bridge.id,
                   desired: %{power: :on},
                   apply_opts: %{transition_ms: 1_000}
                 }
               ],
               server: :executor_transition_settlement,
               mode: :replace
             )

    Executor.tick(:executor_transition_settlement, force: true)
    assert_receive {:dispatched, %{id: light_id, attempts: 0}}, 500
    assert light_id == light.id

    Process.sleep(30)
    Executor.tick(:executor_transition_settlement, force: true)

    refute_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 200
  end

  test "a settlement uses the encoded dispatch duration and ignores early verification" do
    parent = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      {:ok, DispatchReceipt.new(1_300)}
    end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_receipt_settlement,
         dispatch_fun: dispatch_fun,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 10}
      )

    {area, bridge, light} = insert_convergence_light("Receipt Settlement")
    _ = area

    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [%{type: :light, id: light.id, bridge_id: bridge.id, desired: %{power: :on}}],
               server: :executor_receipt_settlement,
               mode: :replace
             )

    Executor.tick(:executor_receipt_settlement, force: true)
    assert_receive {:dispatched, %{id: light_id, attempts: 0}}, 500
    assert light_id == light.id

    {{:light, ^light_id}, settlement} =
      :executor_receipt_settlement |> :sys.get_state() |> Map.fetch!(:settlements) |> Enum.at(0)

    assert settlement.effective_transition_ms == 1_300
    assert settlement.settle_at == 1_300

    Agent.update(clock, fn _ -> 100 end)
    send(:executor_receipt_settlement, {:verify_settlement, settlement.dispatch_id})
    Process.sleep(10)

    refute_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 50
    assert Executor.stats(:executor_receipt_settlement).settlements == 1
  end

  test "a dispatch that omits transition support uses the ordinary settlement floor" do
    parent = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_unsupported_transition,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 750}
      )

    {_area, bridge, light} = insert_convergence_light("Unsupported Transition")
    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [
                 %{
                   type: :light,
                   id: light.id,
                   bridge_id: bridge.id,
                   desired: %{power: :on},
                   apply_opts: %{transition_ms: 30_000}
                 }
               ],
               server: :executor_unsupported_transition,
               mode: :replace
             )

    Executor.tick(:executor_unsupported_transition, force: true)
    assert_receive {:dispatched, %{id: light_id, attempts: 0}}, 500
    assert light_id == light.id

    settlement = current_settlement(:executor_unsupported_transition, light.id)
    assert settlement.effective_transition_ms == 0
    assert settlement.settle_at == 750
  end

  test "a stale desired revision makes its later settlement verification a no-op" do
    parent = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_stale_settlement,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 10}
      )

    {_area, bridge, light} = insert_convergence_light("Stale Settlement")
    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    enqueue_convergence_action(:executor_stale_settlement, bridge, light)
    Executor.tick(:executor_stale_settlement, force: true)
    assert_receive {:dispatched, %{id: light_id, attempts: 0}}, 500
    assert light_id == light.id

    settlement = current_settlement(:executor_stale_settlement, light.id)
    _ = DesiredState.put(:light, light.id, %{power: :off})

    Agent.update(clock, fn _ -> settlement.settle_at end)
    send(:executor_stale_settlement, {:verify_settlement, settlement.dispatch_id})
    Process.sleep(10)

    refute_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 50
    assert Executor.stats(:executor_stale_settlement).settlements == 0
  end

  test "a newer dispatch with the same desired revision supersedes the older settlement" do
    parent = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_superseded_settlement,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 1_000}
      )

    {_area, bridge, light} = insert_convergence_light("Superseded Settlement")
    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})
    revision = DesiredState.revision(:light, light.id)

    enqueue_convergence_action(:executor_superseded_settlement, bridge, light)
    Executor.tick(:executor_superseded_settlement, force: true)
    assert_receive {:dispatched, %{id: light_id, attempts: 0}}, 500
    assert light_id == light.id
    first = current_settlement(:executor_superseded_settlement, light.id)

    enqueue_convergence_action(:executor_superseded_settlement, bridge, light)
    Executor.tick(:executor_superseded_settlement, force: true)
    assert_receive {:dispatched, %{id: ^light_id, attempts: 0}}, 500
    second = current_settlement(:executor_superseded_settlement, light.id)

    assert DesiredState.revision(:light, light.id) == revision
    assert second.dispatch_id > first.dispatch_id

    Agent.update(clock, fn _ -> first.settle_at end)
    send(:executor_superseded_settlement, {:verify_settlement, first.dispatch_id})
    Process.sleep(10)

    refute_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 50

    assert current_settlement(:executor_superseded_settlement, light.id).dispatch_id ==
             second.dispatch_id
  end

  test "partial supersession of a group settlement only recovers its remaining member" do
    parent = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_partial_group_settlement,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 1_000}
      )

    {area, bridge, light_a} = insert_convergence_light("Partial Group A")

    light_b =
      Repo.insert!(%Light{
        name: "Partial Group B Lamp",
        source: :hue,
        source_id: "partial-group-b-#{System.unique_integer([:positive])}",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    group =
      Repo.insert!(%Group{
        name: "Partial Group",
        source: :hue,
        source_id: "partial-group-#{System.unique_integer([:positive])}",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    for light <- [light_a, light_b] do
      _ = DesiredState.put(:light, light.id, %{power: :on})
      _ = State.put(:light, light.id, %{power: :off})
    end

    assert :ok ==
             Executor.enqueue(
               [
                 %{
                   type: :group,
                   id: group.id,
                   bridge_id: bridge.id,
                   light_ids: [light_a.id, light_b.id],
                   desired: %{power: :on}
                 }
               ],
               server: :executor_partial_group_settlement,
               mode: :replace
             )

    Executor.tick(:executor_partial_group_settlement, force: true)
    assert_receive {:dispatched, %{type: :group, id: group_id, attempts: 0}}, 500
    assert group_id == group.id
    group_settlement = current_settlement(:executor_partial_group_settlement, light_b.id)

    assert :ok ==
             Executor.enqueue(
               [
                 %{
                   type: :light,
                   id: light_a.id,
                   bridge_id: bridge.id,
                   desired: %{power: :on}
                 }
               ],
               server: :executor_partial_group_settlement,
               mode: :replace
             )

    Executor.tick(:executor_partial_group_settlement, force: true)
    assert_receive {:dispatched, %{type: :light, id: light_a_id, attempts: 0}}, 500
    assert light_a_id == light_a.id

    Agent.update(clock, fn _ -> group_settlement.settle_at end)
    send(:executor_partial_group_settlement, {:verify_settlement, group_settlement.dispatch_id})
    Process.sleep(10)

    Executor.tick(:executor_partial_group_settlement, force: true)

    assert_receive {:dispatched, %{type: :light, id: light_b_id, attempts: 1}}, 500
    assert light_b_id == light_b.id
    refute_receive {:dispatched, %{type: :group, id: ^group_id, attempts: 1}}, 50
  end

  test "convergence recovery preserves the original custom scene policy" do
    assert_recovery_policy(
      :executor_custom_policy_recovery,
      Operation.new(
        origin: :scene_activation,
        transition_policy: TransitionPolicy.new(30_000, :none)
      ),
      %{transition_ms: 30_000}
    )
  end

  test "convergence recovery preserves the fixed circadian policy" do
    assert_recovery_policy(
      :executor_circadian_policy_recovery,
      Operation.new(origin: :circadian, transition_policy: TransitionPolicy.circadian()),
      %{transition_ms: 500}
    )
  end

  test "presence-scoped recovery cannot expand into an unrelated hardware group" do
    parent = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_presence_scope_recovery,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 10}
      )

    {area, bridge, light_a} = insert_convergence_light("Presence Scope A")

    light_b =
      Repo.insert!(%Light{
        name: "Presence Scope B Lamp",
        source: :hue,
        source_id: "presence-scope-b-#{System.unique_integer([:positive])}",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    group =
      Repo.insert!(%Group{
        name: "Presence Scope Group",
        source: :hue,
        source_id: "presence-scope-group-#{System.unique_integer([:positive])}",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    desired = %{power: :on, brightness: 40}

    for light <- [light_a, light_b] do
      _ = DesiredState.put(:light, light.id, desired)
      _ = State.put(:light, light.id, %{power: :off})
    end

    operation = Operation.new(origin: :presence)

    assert [initial_action] =
             Hueworks.Control.Planner.plan_area(
               area.id,
               %{{:light, light_a.id} => desired},
               operation: operation,
               group_candidate_light_ids: [light_a.id]
             )

    assert initial_action.type == :light
    assert initial_action.id == light_a.id

    assert :ok ==
             Executor.enqueue([initial_action],
               server: :executor_presence_scope_recovery,
               mode: :replace
             )

    Executor.tick(:executor_presence_scope_recovery, force: true)
    assert_receive {:dispatched, %{type: :light, id: light_a_id, attempts: 0}}, 500
    assert light_a_id == light_a.id

    settlement = current_settlement(:executor_presence_scope_recovery, light_a.id)
    Agent.update(clock, fn _ -> settlement.settle_at end)
    send(:executor_presence_scope_recovery, {:verify_settlement, settlement.dispatch_id})
    Process.sleep(10)

    Executor.tick(:executor_presence_scope_recovery, force: true)

    assert_receive {:dispatched, %{type: :light, id: ^light_a_id, attempts: 1}}, 500
    group_id = group.id
    refute_receive {:dispatched, %{type: :group, id: ^group_id, attempts: 1}}, 50
  end

  defp enqueue_convergence_action(server, bridge, light) do
    assert :ok ==
             Executor.enqueue(
               [%{type: :light, id: light.id, bridge_id: bridge.id, desired: %{power: :on}}],
               server: server,
               mode: :replace
             )
  end

  defp current_settlement(server, light_id) do
    server
    |> :sys.get_state()
    |> Map.fetch!(:settlements)
    |> Map.fetch!({:light, light_id})
  end

  defp insert_convergence_light(name) do
    area = Repo.insert!(%Area{name: "#{name} Area"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "#{name} Hue Bridge",
        host: "10.0.0.#{System.unique_integer([:positive])}",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "#{name} Lamp",
        source: :hue,
        source_id: "#{name}-#{System.unique_integer([:positive])}",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    {area, bridge, light}
  end

  defp assert_recovery_policy(server, operation, expected_apply_opts) do
    parent = self()
    clock = start_supervised!({Agent, fn -> 0 end})

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: server,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         bridge_rate_fun: fn _ -> 20 end,
         settlement_floor_ms: 10}
      )

    {_area, bridge, light} = insert_convergence_light("#{server}")
    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [
                 %{
                   type: :light,
                   id: light.id,
                   bridge_id: bridge.id,
                   desired: %{power: :on},
                   operation: operation
                 }
               ],
               server: server,
               mode: :replace
             )

    Executor.tick(server, force: true)
    assert_receive {:dispatched, %{id: light_id, attempts: 0}}, 500
    assert light_id == light.id

    settlement = current_settlement(server, light.id)
    Agent.update(clock, fn _ -> settlement.settle_at end)
    send(server, {:verify_settlement, settlement.dispatch_id})
    Process.sleep(10)

    Executor.tick(server, force: true)

    assert_receive {
                     :dispatched,
                     %{
                       id: ^light_id,
                       attempts: 1,
                       apply_opts: ^expected_apply_opts,
                       operation: ^operation
                     }
                   },
                   500
  end
end
