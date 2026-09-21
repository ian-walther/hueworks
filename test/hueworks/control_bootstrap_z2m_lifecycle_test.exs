defmodule Hueworks.Control.Bootstrap.Z2MLifecycleTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Bootstrap.Z2M
  alias Hueworks.Schemas.Light

  setup do
    for {key, value} <- [
          z2m_bootstrap_tortoise_supervisor_module: __MODULE__.SupervisorStub,
          z2m_bootstrap_tortoise_connection_module: __MODULE__.ConnectionStub,
          z2m_bootstrap_test_sink: self()
        ] do
      old = Application.get_env(:hueworks, key)
      Application.put_env(:hueworks, key, value)
      on_exit(fn -> restore_app_env(:hueworks, key, old) end)
    end

    bridge =
      insert_bridge!(%{
        name: "Z2M",
        type: :z2m,
        host: "unused.invalid",
        credentials: %{"base_topic" => "z2m"}
      })

    Repo.insert!(%Light{name: "Strip", source: :z2m, source_id: "strip", bridge_id: bridge.id})
    %{bridge: bridge}
  end

  test "temporary MQTT connections die with a killed bootstrap task", %{bridge: bridge} do
    task = Task.async(fn -> Z2M.run(bridge) end)
    assert_receive {:temporary_client, client}, 1_000
    monitor = Process.monitor(client)
    Task.shutdown(task, :brutal_kill)
    assert_receive {:DOWN, ^monitor, :process, ^client, _}, 1_000
  end

  defmodule ConnectionStub do
    def connection(_, _), do: Process.sleep(:infinity)
  end

  defmodule SupervisorStub do
    def start_child(opts), do: start_child(opts, nil)

    def start_child(_opts, supervisor) do
      sink = Application.fetch_env!(:hueworks, :z2m_bootstrap_test_sink)
      run = fn -> Process.sleep(:infinity) end

      result =
        if supervisor,
          do: DynamicSupervisor.start_child(supervisor, {Task, run}),
          else: Task.start(run)

      {:ok, client} = result
      send(sink, {:temporary_client, client})
      result
    end
  end
end
