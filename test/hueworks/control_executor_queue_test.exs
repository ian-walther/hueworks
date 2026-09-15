defmodule Hueworks.Control.ExecutorQueueTest do
  use Hueworks.DataCase, async: false

  import ExUnit.CaptureLog

  alias Hueworks.Control.Executor

  setup do
    original = Application.get_env(:hueworks, :control_executor_enabled)
    Application.put_env(:hueworks, :control_executor_enabled, true)
    original_server = Application.get_env(:hueworks, :control_executor_server)
    Application.put_env(:hueworks, :control_executor_server, nil)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original)
      restore_app_env(:hueworks, :control_executor_server, original_server)
    end)

    :ok
  end

  test "enqueue replace overwrites queued actions for the bridge" do
    {:ok, actions_agent} =
      start_supervised({Agent, fn -> [] end}, id: :executor_replace_actions)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      :ok
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_replace_now)
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_replace,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 5 end}
      )

    assert :ok ==
             Executor.enqueue([%{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}],
               server: :executor_replace,
               mode: :replace
             )

    assert :ok ==
             Executor.enqueue([%{type: :light, id: 2, bridge_id: 10, desired: %{power: :on}}],
               server: :executor_replace,
               mode: :replace
             )

    Agent.update(now_agent, fn _ -> -900 end)
    Process.sleep(10)
    Executor.tick(:executor_replace, force: true)

    actions = Agent.get(actions_agent, & &1)
    assert Enum.map(actions, & &1.id) == [2]
  end

  test "enqueue append keeps queued actions for the bridge" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_append_now)
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_append,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 5 end}
      )

    assert :ok ==
             Executor.enqueue([%{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}],
               server: :executor_append,
               mode: :append
             )

    assert :ok ==
             Executor.enqueue([%{type: :light, id: 2, bridge_id: 10, desired: %{power: :on}}],
               server: :executor_append,
               mode: :append
             )

    Executor.tick(:executor_append, force: true)
    assert_receive {:dispatched, %{id: 1}}

    Agent.update(now_agent, fn _ -> 1_400 end)
    Executor.tick(:executor_append, force: true)
    assert_receive {:dispatched, %{id: 2}}
  end

  test "single tick dispatches one due action per bridge" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action.bridge_id, action.id})
      :ok
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_multi_bridge_now)
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_multi_bridge,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 10 end}
      )

    assert :ok ==
             Executor.enqueue(
               [
                 %{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}},
                 %{type: :light, id: 2, bridge_id: 11, desired: %{power: :on}}
               ],
               server: :executor_multi_bridge,
               mode: :append
             )

    assert %{had_work: true, has_pending: false} =
             Executor.tick(:executor_multi_bridge, force: true)

    assert_receive {:dispatched, 10, 1}
    assert_receive {:dispatched, 11, 2}
  end

  test "tick reply reports remaining pending work for same-bridge queue" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action.id})
      :ok
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_tick_status_now)
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_tick_status,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 5 end}
      )

    assert :ok ==
             Executor.enqueue(
               [
                 %{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}},
                 %{type: :light, id: 2, bridge_id: 10, desired: %{power: :on}}
               ],
               server: :executor_tick_status,
               mode: :append
             )

    assert %{had_work: true, has_pending: true} =
             Executor.tick(:executor_tick_status, force: true)

    assert_receive {:dispatched, 1}

    Agent.update(now_agent, fn _ -> 1_400 end)

    assert %{had_work: true, has_pending: false} =
             Executor.tick(:executor_tick_status, force: true)

    assert_receive {:dispatched, 2}
  end

  test "retry backoff requeues failed actions" do
    parent = self()
    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_retry_now)

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})

      case action.attempts do
        0 -> {:error, :failed}
        _ -> :ok
      end
    end

    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_retry,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         max_retries: 2,
         backoff_ms: 250,
         bridge_rate_fun: fn _ -> 5 end}
      )

    assert :ok ==
             Executor.enqueue([%{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}],
               server: :executor_retry,
               mode: :replace
             )

    Executor.tick(:executor_retry)
    assert_receive {:dispatched, %{id: 1, attempts: 0}}

    Agent.update(now_agent, fn _ -> 1_100 end)
    Executor.tick(:executor_retry)
    refute_receive {:dispatched, %{id: 1, attempts: 1}}

    Agent.update(now_agent, fn _ -> 1_400 end)
    Executor.tick(:executor_retry)
    assert_receive {:dispatched, %{id: 1, attempts: 1}}
  end

  test "retry exhaustion logs a warning before dropping the action" do
    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_exhausted_now)

    dispatch_fun = fn _action -> {:error, :failed} end
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_exhausted,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         max_retries: 1,
         backoff_ms: 250,
         bridge_rate_fun: fn _ -> 5 end}
      )

    assert :ok ==
             Executor.enqueue([%{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}],
               server: :executor_exhausted,
               mode: :replace
             )

    log =
      capture_log(fn ->
        Executor.tick(:executor_exhausted)
        Agent.update(now_agent, fn _ -> 1_400 end)
        Executor.tick(:executor_exhausted)
      end)

    assert log =~ "executor_retry_exhausted"
    assert log =~ "type=:light"
    assert log =~ "id=1"
  end

  test "initial enqueue schedules immediate dispatch with negative monotonic time" do
    parent = self()
    {:ok, now_agent} = start_supervised({Agent, fn -> -1_000 end}, id: :executor_negative_now)

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, pid} =
      start_supervised(
        {Executor,
         name: :executor_negative,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 10 end}
      )

    ref = Process.monitor(pid)

    assert :ok ==
             Executor.enqueue([%{type: :group, id: 13, bridge_id: 1, desired: %{power: :on}}],
               server: :executor_negative,
               mode: :replace
             )

    Process.sleep(10)
    Executor.tick(:executor_negative, force: true)
    assert_receive {:dispatched, %{id: 13}}, 500
    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 50
  end

  test "group actions are paced at the group rate while light actions on the bridge continue" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action.type, action.id})
      :ok
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_group_now)
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_group_pacing,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 10 end,
         group_rate_fun: fn _ -> 1 end}
      )

    assert :ok ==
             Executor.enqueue(
               [
                 %{type: :group, id: 1, bridge_id: 10, desired: %{brightness: 40}},
                 %{type: :group, id: 2, bridge_id: 10, desired: %{brightness: 60}},
                 %{type: :light, id: 3, bridge_id: 10, desired: %{brightness: 80}}
               ],
               server: :executor_group_pacing,
               mode: :append
             )

    Executor.tick(:executor_group_pacing)
    assert_receive {:dispatched, :group, 1}

    # 100 ms later the bridge may take another command, but not another group command.
    Agent.update(now_agent, fn _ -> 1_100 end)
    Executor.tick(:executor_group_pacing)
    assert_receive {:dispatched, :light, 3}
    refute_received {:dispatched, :group, 2}

    Agent.update(now_agent, fn _ -> 1_500 end)
    Executor.tick(:executor_group_pacing)
    refute_received {:dispatched, :group, 2}

    Agent.update(now_agent, fn _ -> 2_000 end)
    Executor.tick(:executor_group_pacing)
    assert_receive {:dispatched, :group, 2}
  end

  test "a rejected bridge response is dropped while a busy one is retried" do
    {:ok, results} =
      start_supervised(
        {Agent,
         fn ->
           [
             {:error, {:hue_rejected, [%{"type" => 201}]}},
             {:error, {:hue_busy, [%{"type" => 901}]}}
           ]
         end},
        id: :executor_result_results
      )

    dispatch_fun = fn _action ->
      Agent.get_and_update(results, fn [result | rest] -> {result, rest} end)
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end}, id: :executor_result_now)
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_results,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 10 end}
      )

    # Enqueueing schedules the executor's own tick, which may dispatch before the forced
    # one, so the enqueue is captured too.
    log =
      capture_log(fn ->
        assert :ok ==
                 Executor.enqueue(
                   [%{type: :light, id: 1, bridge_id: 10, desired: %{brightness: 40}}],
                   server: :executor_results,
                   mode: :append
                 )

        Executor.tick(:executor_results, force: true)
      end)

    assert log =~ "executor_dispatch_rejected"
    assert Executor.stats(:executor_results).queues == %{10 => 0}

    assert :ok ==
             Executor.enqueue([%{type: :light, id: 2, bridge_id: 10, desired: %{brightness: 40}}],
               server: :executor_results,
               mode: :append
             )

    Executor.tick(:executor_results, force: true)
    assert Executor.stats(:executor_results).queues == %{10 => 1}
  end
end
