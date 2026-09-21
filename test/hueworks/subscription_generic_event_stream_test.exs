defmodule Hueworks.Subscription.GenericEventStreamTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Subscription.GenericEventStream
  alias __MODULE__.{Connection, ReplacementConnection}

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

  test "explicit refresh reloads only the affected connection and repeated bootstrap does not duplicate it" do
    first = bridge("first.invalid")
    second = bridge("second.invalid")
    manager = manager(Connection)
    first_id = first.id
    second_id = second.id
    assert_receive {:connection_attempt, ^first_id, first_pid}
    assert_receive {:connection_attempt, ^second_id, second_pid}
    Repo.update!(Ecto.Changeset.change(first, host: "updated.invalid"))

    assert :ok = GenericEventStream.refresh(manager, first.id)
    assert_receive {:refreshed, ^first_pid, "updated.invalid"}
    refute_receive {:refreshed, ^second_pid, _}
    send(manager, :retry_bootstrap)
    send(manager, {:restart, first})
    :sys.get_state(manager)
    refute_receive {:connection_attempt, _, _}, 30
    assert map_size(:sys.get_state(manager).monitors) == 2
  end

  test "targeted replacement removes the old monitor and cannot trigger a duplicate restart" do
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: :replacement_connections})
    bridge = bridge("replacement.invalid")
    id = bridge.id
    manager = manager(ReplacementConnection)
    assert_receive {:connection_attempt, ^id, first}
    assert :ok = GenericEventStream.refresh(manager, id)
    assert_receive {:connection_attempt, ^id, second}
    refute Process.alive?(first)
    assert first != second
    assert_single_tracked_connection(manager, id, second)
    send(manager, {:restart, bridge})
    send(manager, :retry_bootstrap)
    assert_single_tracked_connection(manager, id, second)
    refute_receive {:connection_attempt, _, _}, 50
  end

  test "refresh starts an untracked bridge and rejects disabled, deleted and I/O-disabled bridges" do
    manager = manager(Connection)
    bridge = bridge("new.invalid")
    id = bridge.id
    assert :ok = GenericEventStream.refresh(manager, id)
    assert_receive {:connection_attempt, ^id, child}
    assert_single_tracked_connection(manager, id, child)

    old = Application.get_env(:hueworks, :runtime_io_disabled)
    Application.put_env(:hueworks, :runtime_io_disabled, true)
    on_exit(fn -> restore_app_env(:hueworks, :runtime_io_disabled, old) end)
    assert {:error, :runtime_io_disabled} = GenericEventStream.refresh(manager, id)
    Application.put_env(:hueworks, :runtime_io_disabled, false)
    Repo.update!(Ecto.Changeset.change(bridge, enabled: false))
    assert {:error, :bridge_unavailable} = GenericEventStream.refresh(manager, id)
    Repo.delete!(bridge)
    assert {:error, :bridge_unavailable} = GenericEventStream.refresh(manager, id)
  end

  defp bridge(host),
    do: insert_bridge!(%{type: :hue, name: "Hue", host: host, credentials: %{"api_key" => "key"}})

  defp manager(module) do
    start_supervised!(
      {GenericEventStream,
       name: :test_refresh_stream,
       bridge_type: :hue,
       connection_module: module,
       restart_delay_ms: 10}
    )
  end

  defmodule Connection do
    def refresh(pid, bridge) do
      send(Process.whereis(:generic_stream_test_listener), {:refreshed, pid, bridge.host})
      {:ok, pid}
    end

    def start_link(bridge) do
      {:ok, pid} = Task.start_link(fn -> Process.sleep(:infinity) end)

      if listener = Process.whereis(:generic_stream_test_listener) do
        send(listener, {:connection_attempt, bridge.id, pid})
      end

      {:ok, pid}
    end
  end

  defmodule ReplacementConnection do
    def start_link(bridge) do
      {:ok, pid} =
        DynamicSupervisor.start_child(:replacement_connections, {Agent, fn -> bridge.id end})

      send(Process.whereis(:generic_stream_test_listener), {:connection_attempt, bridge.id, pid})
      {:ok, pid}
    end

    def refresh(pid, bridge) do
      :ok = DynamicSupervisor.terminate_child(:replacement_connections, pid)
      start_link(bridge)
    end
  end
end
