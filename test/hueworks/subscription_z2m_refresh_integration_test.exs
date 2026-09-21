defmodule Hueworks.Subscription.Z2MRefreshIntegrationTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State
  alias Hueworks.Schemas.Light
  alias Hueworks.Subscription.Z2MEventStream.Connection
  alias Tortoise.Package

  test "replacement waits for the old MQTT handler tree and loads new identities" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)
    owner = self()
    tasks = start_supervised!({Task.Supervisor, []})
    Task.Supervisor.start_child(tasks, fn -> accept(listener, tasks, owner) end)

    bridge =
      insert_bridge!(%{
        name: "Loopback MQTT",
        type: :z2m,
        host: "127.0.0.1",
        credentials: %{"broker_port" => port, "base_topic" => "test"}
      })

    light =
      Repo.insert!(%Light{name: "Strip", source: :z2m, source_id: "before", bridge_id: bridge.id})

    client_id = Connection.subscription_client_id(bridge.id)

    on_exit(fn ->
      if pid = registered(Tortoise.Connection, client_id),
        do: DynamicSupervisor.terminate_child(Tortoise.Supervisor, pid)
    end)

    assert {:ok, first} = Connection.start_link(bridge)
    assert_receive {:mqtt_ready, ^client_id, _socket}, 1_000
    connection_tree = registered(Tortoise.Connection.Supervisor, client_id)
    {:ok, slow_child} = Supervisor.start_child(connection_tree, {__MODULE__.SlowChild, owner})
    on_exit(fn -> send(slow_child, :finish_shutdown) end)
    Repo.update!(Ecto.Changeset.change(light, source_id: "after"))
    task = Task.async(fn -> Connection.refresh(first, bridge) end)

    # A slow old handler must not be reused by the replacement connection.
    assert_receive {:stopping, ^slow_child}, 1_000
    assert Task.yield(task, 50) == nil
    send(slow_child, :finish_shutdown)
    assert {:ok, replacement} = Task.await(task, 2_000)
    assert replacement != first
    assert_receive {:mqtt_ready, ^client_id, socket}, 1_000
    Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")

    :ok =
      :gen_tcp.send(
        socket,
        Package.encode(%Package.Publish{
          topic: "test/after",
          payload: ~s({"state":"ON","brightness":254}),
          qos: 0
        })
      )

    id = light.id
    assert_receive {:control_state, :light, ^id, %{power: :on, brightness: 100}}, 1_000
    assert %{brightness: 100} = State.get(:light, light.id)
    :ok = DynamicSupervisor.terminate_child(Tortoise.Supervisor, replacement)
  end

  defp registered(module, id), do: GenServer.whereis(Tortoise.Registry.via_name(module, id))

  defmodule SlowChild do
    use GenServer
    def start_link(owner), do: GenServer.start_link(__MODULE__, owner)
    @impl true
    def init(owner) do
      Process.flag(:trap_exit, true)
      {:ok, owner}
    end

    @impl true
    def terminate(_, owner) do
      send(owner, {:stopping, self()})
      receive do: (:finish_shutdown -> :ok)
    end
  end

  defp accept(listener, tasks, owner) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, child} =
          Task.Supervisor.start_child(tasks, fn ->
            receive do: (:start -> serve(socket, owner))
          end)

        :ok = :gen_tcp.controlling_process(socket, child)
        send(child, :start)
        accept(listener, tasks, owner)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(socket, owner) do
    %Package.Connect{client_id: id} = receive_packet(socket)
    :ok = :gen_tcp.send(socket, Package.encode(%Package.Connack{status: :accepted}))
    %Package.Subscribe{identifier: identifier, topics: topics} = receive_packet(socket)

    :ok =
      :gen_tcp.send(
        socket,
        Package.encode(%Package.Suback{
          identifier: identifier,
          acks: Enum.map(topics, fn _ -> {:ok, 0} end)
        })
      )

    send(owner, {:mqtt_ready, id, socket})
    :gen_tcp.recv(socket, 0)
  end

  defp receive_packet(socket) do
    {:ok, header} = :gen_tcp.recv(socket, 1, 2_000)
    {encoded_size, size} = receive_length(socket, 1, 0, <<>>)
    {:ok, body} = :gen_tcp.recv(socket, size, 2_000)
    Package.decode(header <> encoded_size <> body)
  end

  defp receive_length(socket, multiplier, size, encoded) do
    {:ok, <<more::1, digit::7>> = byte} = :gen_tcp.recv(socket, 1, 2_000)
    size = size + digit * multiplier

    if more == 0,
      do: {encoded <> byte, size},
      else: receive_length(socket, multiplier * 128, size, encoded <> byte)
  end
end
