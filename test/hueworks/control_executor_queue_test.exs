defmodule Hueworks.Control.ExecutorQueueTest do
  use ExUnit.Case, async: false

  alias Hueworks.Control.Executor

  setup do
    original = Application.get_env(:hueworks, :control_executor_enabled)
    Application.put_env(:hueworks, :control_executor_enabled, true)
    original_server = Application.get_env(:hueworks, :control_executor_server)
    Application.put_env(:hueworks, :control_executor_server, nil)

    on_exit(fn ->
      Application.put_env(:hueworks, :control_executor_enabled, original)
      Application.put_env(:hueworks, :control_executor_server, original_server)
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

  test "initial enqueue schedules immediate dispatch with negative monotonic time" do
    parent = self()
    {:ok, now_agent} = start_supervised({Agent, fn -> -1_000 end}, id: :executor_negative_now)

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_negative,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 10 end}
      )

    assert :ok ==
             Executor.enqueue([%{type: :group, id: 13, bridge_id: 1, desired: %{power: :on}}],
               server: :executor_negative,
               mode: :replace
             )

    Process.sleep(10)
    Executor.tick(:executor_negative, force: true)
    assert_receive {:dispatched, %{id: 13}}, 500
  end
end
