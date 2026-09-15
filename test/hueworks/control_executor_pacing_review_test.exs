defmodule Hueworks.Control.ExecutorPacingReviewTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Executor

  setup do
    original = Application.get_env(:hueworks, :control_executor_enabled)
    Application.put_env(:hueworks, :control_executor_enabled, true)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original)
    end)

    :ok
  end

  test "a busy group retry waits for both its backoff and the group request budget" do
    {server, clock, calls} =
      executor(fn action ->
        if action.attempts == 0, do: busy(), else: :ok
      end)

    enqueue(server, [group(1)])
    tick_at(server, clock, 1_000)
    assert attempts(calls) == [{1, 0, 1_000}]

    tick_at(server, clock, 1_250)
    assert attempts(calls) == [{1, 0, 1_000}]

    tick_at(server, clock, 2_000)
    assert attempts(calls) == [{1, 0, 1_000}, {1, 1, 2_000}]
  end

  test "a busy group consumes the budget for a different queued group too" do
    {server, clock, calls} = executor(fn _action -> busy() end)

    enqueue(server, [group(1), group(2)])
    tick_at(server, clock, 1_000)

    tick_at(server, clock, 1_100)
    assert attempts(calls) == [{1, 0, 1_000}]

    tick_at(server, clock, 2_000)
    assert attempts(calls) == [{1, 0, 1_000}, {2, 0, 2_000}]
  end

  @tag capture_log: true
  test "a permanently refused group still consumes the bridge request budget" do
    {server, clock, calls} =
      executor(fn _action ->
        {:error, {:hue_rejected, [%{"type" => 201, "description" => "device is set to off"}]}}
      end)

    enqueue(server, [group(1), group(2)])
    tick_at(server, clock, 1_000)

    tick_at(server, clock, 1_100)
    assert attempts(calls) == [{1, 0, 1_000}]

    tick_at(server, clock, 2_000)
    assert attempts(calls) == [{1, 0, 1_000}, {2, 0, 2_000}]
    assert Executor.stats(server).queues == %{10 => 0}
  end

  test "successful groups remain spaced while an unrelated light can bypass the wait" do
    {server, clock, calls} = executor(fn _action -> :ok end)

    enqueue(server, [group(1), group(2), %{group(3) | type: :light}])
    tick_at(server, clock, 1_000)
    tick_at(server, clock, 1_100)
    tick_at(server, clock, 1_999)
    assert attempts(calls) == [{1, 0, 1_000}, {3, 0, 1_100}]

    tick_at(server, clock, 2_000)
    assert attempts(calls) == [{1, 0, 1_000}, {3, 0, 1_100}, {2, 0, 2_000}]
  end

  test "group spacing uses each request start, not the start of a multi-bridge tick" do
    {server, clock, calls} =
      executor(fn _action -> :ok end, fn _action, clock ->
        # Model one bridge taking 800 ms to answer before this tick reaches the other.
        Agent.update(clock, fn
          1_000 -> 1_800
          now -> now
        end)
      end)

    enqueue(server, [group(1), group(2), %{group(3) | bridge_id: 20}, %{group(4) | bridge_id: 20}])

    tick_at(server, clock, 1_000)
    assert length(attempts(calls)) == 2
    assert attempts(calls) |> Enum.map(&elem(&1, 2)) |> Enum.sort() == [1_000, 1_800]

    tick_at(server, clock, 2_000)
    tick_at(server, clock, 2_800)
    assert length(attempts(calls)) == 4

    for ids <- [[1, 2], [3, 4]] do
      [first, second] =
        attempts(calls)
        |> Enum.filter(fn {id, _, _} -> id in ids end)
        |> Enum.map(&elem(&1, 2))

      assert second - first >= 1_000,
             "groups #{inspect(ids)} were sent only #{second - first} ms apart"
    end
  end

  defp executor(result_fun, before_reply \\ fn _action, _clock -> :ok end) do
    clock = start_supervised!({Agent, fn -> 0 end}, id: :clock)
    calls = start_supervised!({Agent, fn -> [] end}, id: :calls)

    server =
      start_supervised!(
        {Executor,
         name: nil,
         bridge_rate_fun: fn _ -> 10 end,
         group_rate_fun: fn _ -> 1 end,
         now_fn: fn :millisecond -> Agent.get(clock, & &1) end,
         dispatch_fun: fn action ->
           now = Agent.get(clock, & &1)
           Agent.update(calls, &(&1 ++ [{action.id, action.attempts, now}]))
           before_reply.(action, clock)
           result_fun.(action)
         end}
      )

    {server, clock, calls}
  end

  defp group(id) do
    %{
      type: :group,
      id: id,
      bridge_id: 10,
      desired: %{power: :on},
      light_ids: [],
      not_before: 1_000
    }
  end

  defp enqueue(server, actions) do
    assert :ok = Executor.enqueue(actions, server: server, mode: :append)
    # Automatic timer ticks see time zero until the test advances the clock.
    Executor.tick(server)
  end

  defp tick_at(server, clock, now) do
    Agent.update(clock, fn _ -> now end)
    Executor.tick(server)
  end

  defp attempts(calls), do: Agent.get(calls, & &1)

  defp busy, do: {:error, {:hue_busy, [%{"type" => 901, "description" => "bridge busy"}]}}
end
