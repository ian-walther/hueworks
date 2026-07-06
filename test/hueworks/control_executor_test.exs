defmodule Hueworks.Control.ExecutorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Hueworks.Control.Executor

  test "failed actions are retried only after exponential backoff elapses" do
    parent = self()
    name = :"executor_test_#{System.unique_integer([:positive])}"
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    previous_enabled = Application.get_env(:hueworks, :control_executor_enabled)

    Application.put_env(:hueworks, :control_executor_enabled, true)

    on_exit(fn ->
      if is_nil(previous_enabled) do
        Application.delete_env(:hueworks, :control_executor_enabled)
      else
        Application.put_env(:hueworks, :control_executor_enabled, previous_enabled)
      end
    end)

    dispatch_fun = fn action ->
      send(parent, {:dispatch, action})
      {:error, :boom}
    end

    {:ok, pid} =
      Executor.start_link(
        name: name,
        now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
        dispatch_fun: dispatch_fun,
        bridge_rate_fun: fn _bridge_id -> 1000 end,
        backoff_ms: 100,
        max_retries: 2
      )

    action = %{type: :light, id: 1, bridge_id: 10, desired: %{power: :on}}

    assert :ok == Executor.enqueue([action], server: name)
    assert_receive {:dispatch, %{attempts: 0, not_before: 0}}
    refute_receive {:dispatch, _}, 25

    Agent.update(clock, fn _ -> 99 end)
    assert %{had_work: false, has_pending: true} = Executor.tick(name)
    refute_receive {:dispatch, _}, 25

    Agent.update(clock, fn _ -> 100 end)
    assert %{has_pending: true} = Executor.tick(name)
    assert_receive {:dispatch, %{attempts: 1, not_before: 100}}

    Agent.update(clock, fn _ -> 299 end)
    assert %{had_work: false, has_pending: true} = Executor.tick(name)
    refute_receive {:dispatch, _}, 25

    log =
      capture_log(fn ->
        Agent.update(clock, fn _ -> 300 end)
        assert %{has_pending: false} = Executor.tick(name)
        assert_receive {:dispatch, %{attempts: 2, not_before: 300}}
      end)

    assert log =~ "executor_retry_exhausted"

    GenServer.stop(pid)
    Agent.stop(clock)
  end
end
