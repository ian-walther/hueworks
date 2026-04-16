defmodule Hueworks.Subscription.CasetaEventStreamTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Subscription.CasetaEventStream

  defmodule FakeConnection do
    def start_link(bridge) do
      listener = Process.whereis(:caseta_stream_test_listener)

      case Agent.get(:caseta_stream_test_attempts, &Map.get(&1, bridge.id, 0)) do
        0 ->
          Agent.update(:caseta_stream_test_attempts, &Map.put(&1, bridge.id, 1))
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
      id: :caseta_stream_test_attempts,
      start: {Agent, :start_link, [fn -> %{} end, [name: :caseta_stream_test_attempts]]}
    })
    Process.register(self(), :caseta_stream_test_listener)

    on_exit(fn ->
      if Process.whereis(:caseta_stream_test_listener) == self() do
        Process.unregister(:caseta_stream_test_listener)
      end
    end)

    :ok
  end

  test "retries failed bridge connections and eventually monitors successful ones" do
    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.92",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, _pid} =
      start_supervised(
        {CasetaEventStream,
         [
           name: :caseta_stream_retry_test,
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
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.93",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, readiness_agent} =
      start_supervised(%{
        id: :caseta_stream_readiness,
        start: {Agent, :start_link, [fn -> false end, [name: :caseta_stream_readiness]]}
      })

    {:ok, pid} =
      start_supervised(
        {CasetaEventStream,
         [
           name: :caseta_stream_readiness_test,
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
end
