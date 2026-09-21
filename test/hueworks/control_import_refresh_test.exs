defmodule Hueworks.Control.ImportRefreshTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{BridgeRefresh, ImportRefresh}
  alias Hueworks.DomainEvents

  setup do
    previous = Application.get_env(:hueworks, :runtime_io_disabled)
    Application.put_env(:hueworks, :runtime_io_disabled, false)
    on_exit(fn -> restore_app_env(:hueworks, :runtime_io_disabled, previous) end)
    Phoenix.PubSub.subscribe(Hueworks.PubSub, "bridge_runtime_refresh")
    :ok
  end

  test "an offline bridge does not block another bridge and retry errors are sanitized" do
    owner = self()

    runtime =
      runtime(fn id ->
        send(owner, {:started, id, self()})
        receive do: ({:finish, result} -> result)
      end)

    DomainEvents.bridge_import_applied(1)
    DomainEvents.bridge_import_applied(2)
    assert_receive {:started, 1, first}, 1_000
    assert_receive {:started, 2, second}, 1_000
    send(second, {:finish, :ok})
    assert_receive {:bridge_runtime_refresh, 2, %{state: :ready}}, 1_000
    send(first, {:finish, {:error, "secret-token-and-private-response"}})

    assert_receive {:bridge_runtime_refresh, 1, %{state: :retrying, error: :refresh_failed}},
                   1_000

    refute inspect(ImportRefresh.status(1, runtime)) =~ "secret-token"
  end

  test "imports arriving during a task coalesce into one subsequent refresh" do
    owner = self()

    runtime =
      runtime(fn id ->
        send(owner, {:started, id, self()})
        receive do: (:finish -> :ok)
      end)

    DomainEvents.bridge_import_applied(1)
    assert_receive {:started, 1, first}, 1_000
    for _ <- 1..5, do: DomainEvents.bridge_import_applied(1)
    assert %{state: :refreshing} = ImportRefresh.status(1, runtime)
    refute_receive {:started, 1, _}, 20
    send(first, :finish)
    assert_receive {:started, 1, second}, 1_000
    assert first != second
    send(second, :finish)
    assert_receive {:bridge_runtime_refresh, 1, %{state: :ready}}, 1_000
    refute_receive {:started, 1, _}, 30
  end

  test "a timeout kills the old task before retrying" do
    owner = self()

    runtime(
      fn _ ->
        send(owner, {:started, self()})
        receive do: (:finish -> :ok)
      end, timeout_ms: 100, retry_ms: 10)

    DomainEvents.bridge_import_applied(1)
    assert_receive {:started, first}, 1_000
    monitor = Process.monitor(first)
    assert_receive {:DOWN, ^monitor, :process, ^first, :killed}, 1_000
    assert_receive {:bridge_runtime_refresh, 1, %{state: :retrying, error: :timeout}}, 1_000
    assert_receive {:started, second}, 1_000
    send(second, :finish)
    assert_receive {:bridge_runtime_refresh, 1, %{state: :ready}}, 1_000
  end

  test "a task crash does not kill the refresh service" do
    owner = self()

    runtime =
      runtime(
        fn _ ->
          send(owner, {:started, self()})
          receive do: (:finish -> :ok)
        end,
        retry_ms: 10
      )

    DomainEvents.bridge_import_applied(1)
    assert_receive {:started, first}, 1_000
    Process.exit(first, :kill)
    assert_receive {:bridge_runtime_refresh, 1, %{state: :retrying, error: :task_exit}}, 1_000
    assert_receive {:started, second}, 1_000
    send(second, :finish)
    assert_receive {:bridge_runtime_refresh, 1, %{state: :ready}}, 1_000
    assert Process.alive?(runtime)
  end

  test "a new import cancels an old retry timer" do
    owner = self()

    runtime(
      fn _ ->
        send(owner, {:started, self()})
        receive do: ({:finish, result} -> result)
      end,
      retry_ms: 150
    )

    DomainEvents.bridge_import_applied(1)
    assert_receive {:started, first}, 1_000
    send(first, {:finish, {:error, :indexes}})
    assert_receive {:bridge_runtime_refresh, 1, %{state: :retrying}}, 1_000
    DomainEvents.bridge_import_applied(1)
    assert_receive {:started, second}, 1_000
    send(second, {:finish, :ok})
    assert_receive {:bridge_runtime_refresh, 1, %{state: :ready}}, 1_000
    refute_receive {:started, _}, 200
  end

  test "runtime-I/O-disabled mode skips both automatic and ad hoc refresh" do
    owner = self()
    runtime(fn _ -> send(owner, :unexpected_io) end)
    Application.put_env(:hueworks, :runtime_io_disabled, true)
    DomainEvents.bridge_import_applied(1)
    assert_receive {:bridge_runtime_refresh, 1, %{state: :disabled}}, 1_000
    assert :disabled = BridgeRefresh.run(1)
    refute_receive :unexpected_io, 30
  end

  test "disabling runtime I/O before retry prevents another network attempt" do
    owner = self()

    runtime(
      fn _ ->
        send(owner, :attempt)
        {:error, :observations}
      end, retry_ms: 100)

    DomainEvents.bridge_import_applied(1)
    assert_receive :attempt, 1_000
    assert_receive {:bridge_runtime_refresh, 1, %{state: :retrying}}, 1_000
    Application.put_env(:hueworks, :runtime_io_disabled, true)
    assert_receive {:bridge_runtime_refresh, 1, %{state: :disabled}}, 1_000
    refute_receive :attempt, 30
  end

  test "deleted and disabled bridges are skipped without contacting a transport" do
    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Disabled",
        host: "never-contact.invalid",
        credentials: %{"app_key" => "test-key"},
        enabled: false
      })

    assert :skipped = BridgeRefresh.run(bridge.id)
    Repo.delete!(bridge)
    assert :skipped = BridgeRefresh.run(bridge.id)
  end

  test "normal shutdown cancels active tasks" do
    owner = self()

    runtime(fn _ ->
      send(owner, {:started, self()})
      Process.sleep(:infinity)
    end)

    DomainEvents.bridge_import_applied(1)
    assert_receive {:started, task}, 1_000
    monitor = Process.monitor(task)
    stop_supervised!(ImportRefresh)
    assert_receive {:DOWN, ^monitor, :process, ^task, :killed}, 1_000
  end

  test "startup recovers imported bridges without replaying an import" do
    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Imported",
        host: "unused.invalid",
        credentials: %{"api_key" => "key"},
        import_complete: true
      })

    id = bridge.id
    owner = self()

    runtime(
      fn id ->
        send(owner, {:recovered, id})
        :ok
      end, recover_on_start: true)

    assert_receive {:recovered, ^id}, 1_000
    assert_receive {:bridge_runtime_refresh, ^id, %{state: :ready}}, 1_000
  end

  test "supervision cancels orphan tasks when the coordinator is killed" do
    owner = self()

    start_supervised!(
      {ImportRefresh.Supervisor,
       [
         name: :test_refresh_tree,
         worker_name: :test_refresh_worker,
         task_supervisor: :test_refresh_tasks,
         recover_on_start: false,
         refresh_fun: fn _ ->
           send(owner, {:started, self()})
           Process.sleep(:infinity)
         end
       ]}
    )

    DomainEvents.bridge_import_applied(1)
    assert_receive {:started, task}, 1_000
    monitor = Process.monitor(task)
    Process.exit(Process.whereis(:test_refresh_worker), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^task, _}, 1_000
  end

  defp runtime(refresh, opts \\ []) do
    tasks = start_supervised!({Task.Supervisor, []})

    start_supervised!(
      {ImportRefresh,
       Keyword.merge(
         [
           name: :runtime_refresh_test,
           refresh_fun: refresh,
           task_supervisor: tasks,
           retry_ms: 1_000,
           recover_on_start: false
         ],
         opts
       )}
    )
  end
end
