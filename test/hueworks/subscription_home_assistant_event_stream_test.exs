defmodule Hueworks.Subscription.HomeAssistantEventStreamTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Subscription.HomeAssistantEventStream

  defmodule FakeConnection do
    def start_link(bridge) do
      listener = Process.whereis(:ha_stream_test_listener)

      case Agent.get(:ha_stream_test_attempts, &Map.get(&1, bridge.id, 0)) do
        0 ->
          Agent.update(:ha_stream_test_attempts, &Map.put(&1, bridge.id, 1))
          if listener, do: send(listener, {:connection_attempt, bridge.id, :error})
          {:error, :boom}

        _ ->
          if listener, do: send(listener, {:connection_attempt, bridge.id, :ok})
          Task.start_link(fn -> Process.sleep(:infinity) end)
      end
    end
  end

  setup do
    start_supervised!(%{
      id: :ha_stream_test_attempts,
      start: {Agent, :start_link, [fn -> %{} end, [name: :ha_stream_test_attempts]]}
    })

    Process.register(self(), :ha_stream_test_listener)

    on_exit(fn ->
      if Process.whereis(:ha_stream_test_listener) == self() do
        Process.unregister(:ha_stream_test_listener)
      end
    end)

    :ok
  end

  test "retries failed bridge connections and eventually monitors successful ones" do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.110",
        credentials: %{"token" => "token"},
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, _pid} =
      start_supervised(
        {HomeAssistantEventStream,
         [
           name: :ha_stream_retry_test,
           connection_module: FakeConnection,
           readiness_fun: fn -> true end,
           restart_delay_ms: 10
         ]}
      )

    assert_receive {:connection_attempt, ^bridge_id, :error}, 200
    assert_receive {:connection_attempt, ^bridge_id, :ok}, 500
  end

  test "waits for readiness before starting bridge connections" do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.111",
        credentials: %{"token" => "token"},
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, readiness_agent} =
      start_supervised(%{
        id: :ha_stream_readiness,
        start: {Agent, :start_link, [fn -> false end, [name: :ha_stream_readiness]]}
      })

    {:ok, pid} =
      start_supervised(
        {HomeAssistantEventStream,
         [
           name: :ha_stream_readiness_test,
           connection_module: FakeConnection,
           readiness_fun: fn -> Agent.get(readiness_agent, & &1) end,
           retry_delay_ms: 10,
           restart_delay_ms: 10
         ]}
      )

    refute_receive {:connection_attempt, ^bridge_id, _}, 50

    Agent.update(readiness_agent, fn _ -> true end)
    send(pid, :retry_bootstrap)

    assert_receive {:connection_attempt, ^bridge_id, :error}, 200
  end

  test "starts only enabled bridges of the matching type" do
    target =
      insert_bridge!(%{
        type: :ha,
        name: "HA Target",
        host: "10.0.0.130",
        credentials: %{"token" => "token"},
        enabled: true
      })

    _disabled =
      insert_bridge!(%{
        type: :ha,
        name: "HA Disabled",
        host: "10.0.0.131",
        credentials: %{"token" => "token"},
        enabled: false
      })

    _other_type =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Other",
        host: "10.0.0.132",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    target_id = target.id

    {:ok, _pid} =
      start_supervised(
        {HomeAssistantEventStream,
         [
           name: :ha_stream_filter_test,
           connection_module: __MODULE__.SucceedingConnection,
           readiness_fun: fn -> true end,
           restart_delay_ms: 10
         ]}
      )

    assert_receive {:connection_attempt, ^target_id, :ok}, 200
    refute_receive {:connection_attempt, _, _}, 50
  end

  test "restarts a monitored connection when it exits" do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA Restart",
        host: "10.0.0.133",
        credentials: %{"token" => "token"},
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, pid} =
      start_supervised(
        {HomeAssistantEventStream,
         [
           name: :ha_stream_restart_test,
           connection_module: __MODULE__.SucceedingConnection,
           readiness_fun: fn -> true end,
           restart_delay_ms: 10
         ]}
      )

    assert_receive {:connection_attempt, ^bridge_id, :ok}, 200

    {_child_ref, child_bridge} = hd(Map.to_list(:sys.get_state(pid).monitors))
    assert child_bridge.id == bridge_id
    child_pid = Process.info(pid, :monitors) |> elem(1) |> Keyword.fetch!(:process)
    assert is_pid(child_pid)
    Process.exit(child_pid, :shutdown)

    assert_receive {:connection_attempt, ^bridge_id, :ok}, 200
  end

  defmodule SucceedingConnection do
    def start_link(bridge) do
      listener = Process.whereis(:ha_stream_test_listener)
      if listener, do: send(listener, {:connection_attempt, bridge.id, :ok})
      Task.start_link(fn -> Process.sleep(:infinity) end)
    end
  end

end
