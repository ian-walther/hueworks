defmodule Hueworks.Subscription.HueEventStreamTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Subscription.HueEventStream

  defmodule FakeConnection do
    def start_link(bridge) do
      listener = Process.whereis(:hue_stream_test_listener)

      case Agent.get(:hue_stream_test_attempts, &Map.get(&1, bridge.id, 0)) do
        0 ->
          Agent.update(:hue_stream_test_attempts, &Map.put(&1, bridge.id, 1))
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
      id: :hue_stream_test_attempts,
      start: {Agent, :start_link, [fn -> %{} end, [name: :hue_stream_test_attempts]]}
    })

    Process.register(self(), :hue_stream_test_listener)

    on_exit(fn ->
      if Process.whereis(:hue_stream_test_listener) == self() do
        Process.unregister(:hue_stream_test_listener)
      end
    end)

    :ok
  end

  test "retries failed bridge connections and eventually monitors successful ones" do
    bridge =
      Repo.insert!(%Bridge{
        type: :hue,
        name: "Hue",
        host: "10.0.0.100",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, _pid} =
      start_supervised(
        {HueEventStream,
         [
           name: :hue_stream_retry_test,
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
      Repo.insert!(%Bridge{
        type: :hue,
        name: "Hue",
        host: "10.0.0.101",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    bridge_id = bridge.id

    {:ok, readiness_agent} =
      start_supervised(%{
        id: :hue_stream_readiness,
        start: {Agent, :start_link, [fn -> false end, [name: :hue_stream_readiness]]}
      })

    {:ok, pid} =
      start_supervised(
        {HueEventStream,
         [
           name: :hue_stream_readiness_test,
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
