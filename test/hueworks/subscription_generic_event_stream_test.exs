defmodule Hueworks.Subscription.GenericEventStreamTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Subscription.GenericEventStream

  setup do
    Process.register(self(), :generic_stream_test_listener)

    on_exit(fn ->
      if Process.whereis(:generic_stream_test_listener) == self() do
        Process.unregister(:generic_stream_test_listener)
      end
    end)

    :ok
  end

  test "waits for readiness and restarts monitored connections without replacing the manager" do
    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "10.0.0.91",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, readiness_agent} =
      start_supervised(%{
        id: :generic_stream_readiness,
        start: {Agent, :start_link, [fn -> false end, [name: :generic_stream_readiness]]}
      })

    {:ok, pid} =
      start_supervised(
        {GenericEventStream,
         [
           name: :generic_stream_restart_readiness_test,
           bridge_type: :hue,
           connection_module: __MODULE__.Connection,
           readiness_fun: fn -> Agent.get(readiness_agent, & &1) end,
           retry_delay_ms: 10,
           restart_delay_ms: 10
         ]}
      )

    refute_receive {:connection_attempt, ^bridge_id, _pid}, 50

    Agent.update(readiness_agent, fn _ -> true end)

    assert_receive {:connection_attempt, ^bridge_id, child_pid}, 200
    assert is_pid(child_pid)
    assert_single_tracked_connection(pid, bridge_id, child_pid)

    manager_ref = Process.monitor(pid)
    Process.exit(child_pid, :shutdown)

    assert_receive {:connection_attempt, ^bridge_id, restarted_pid}, 200
    assert is_pid(restarted_pid)
    assert restarted_pid != child_pid
    refute_receive {:DOWN, ^manager_ref, :process, ^pid, _reason}, 50
    assert Process.alive?(pid)
    assert_single_tracked_connection(pid, bridge_id, restarted_pid)

    Process.demonitor(manager_ref, [:flush])
  end

  defp assert_single_tracked_connection(manager_pid, bridge_id, child_pid) do
    state = :sys.get_state(manager_pid)

    assert [{ref, bridge}] = Map.to_list(state.monitors)
    assert bridge.id == bridge_id
    assert state.connection_refs == %{child_pid => ref}
  end

  defmodule Connection do
    def start_link(bridge) do
      {:ok, pid} = Task.start_link(fn -> Process.sleep(:infinity) end)

      if listener = Process.whereis(:generic_stream_test_listener) do
        send(listener, {:connection_attempt, bridge.id, pid})
      end

      {:ok, pid}
    end
  end
end
