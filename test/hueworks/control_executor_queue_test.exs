defmodule Hueworks.Control.ExecutorQueueTest do
  use ExUnit.Case, async: false

  alias Hueworks.Control.Executor

  setup do
    original = Application.get_env(:hueworks, :control_executor_enabled)
    Application.put_env(:hueworks, :control_executor_enabled, true)

    on_exit(fn ->
      Application.put_env(:hueworks, :control_executor_enabled, original)
    end)

    :ok
  end

  test "enqueue replace overwrites queued actions for the bridge" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end})
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, pid} =
      start_supervised(
        {Executor,
         name: :executor_replace,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 5 end}
      )

    Executor.enqueue([%{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}],
      server: :executor_replace,
      mode: :replace
    )

    Executor.enqueue([%{type: :light, id: 2, bridge_id: 10, desired: %{power: :on}}],
      server: :executor_replace,
      mode: :replace
    )

    send(pid, :tick)

    assert_receive {:dispatched, %{id: 2}}
    refute_receive {:dispatched, %{id: 1}}
  end

  test "enqueue append keeps queued actions for the bridge" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end})
    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, pid} =
      start_supervised(
        {Executor,
         name: :executor_append,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         bridge_rate_fun: fn _ -> 5 end}
      )

    Executor.enqueue([%{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}],
      server: :executor_append,
      mode: :append
    )

    Executor.enqueue([%{type: :light, id: 2, bridge_id: 10, desired: %{power: :on}}],
      server: :executor_append,
      mode: :append
    )

    send(pid, :tick)
    assert_receive {:dispatched, %{id: 1}}

    Agent.update(now_agent, fn _ -> 1_400 end)
    send(pid, :tick)
    assert_receive {:dispatched, %{id: 2}}
  end

  test "retry backoff requeues failed actions" do
    parent = self()
    {:ok, now_agent} = start_supervised({Agent, fn -> 1_000 end})

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})

      case action.attempts do
        0 -> {:error, :failed}
        _ -> :ok
      end
    end

    now_fn = fn :millisecond -> Agent.get(now_agent, & &1) end

    {:ok, pid} =
      start_supervised(
        {Executor,
         name: :executor_retry,
         dispatch_fun: dispatch_fun,
         now_fn: now_fn,
         max_retries: 2,
         backoff_ms: 250,
         bridge_rate_fun: fn _ -> 5 end}
      )

    Executor.enqueue([%{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}],
      server: :executor_retry,
      mode: :replace
    )

    send(pid, :tick)
    assert_receive {:dispatched, %{id: 1, attempts: 0}}

    Agent.update(now_agent, fn _ -> 1_100 end)
    send(pid, :tick)
    refute_receive {:dispatched, %{id: 1, attempts: 1}}

    Agent.update(now_agent, fn _ -> 1_400 end)
    send(pid, :tick)
    assert_receive {:dispatched, %{id: 1, attempts: 1}}
  end
end
