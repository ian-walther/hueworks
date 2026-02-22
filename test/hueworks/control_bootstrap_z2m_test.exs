defmodule Hueworks.Control.Bootstrap.Z2MTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Bootstrap.Z2M
  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, Room}

  setup do
    original_tortoise = Application.get_env(:hueworks, :z2m_bootstrap_tortoise_module)

    original_supervisor =
      Application.get_env(:hueworks, :z2m_bootstrap_tortoise_supervisor_module)

    original_connection =
      Application.get_env(:hueworks, :z2m_bootstrap_tortoise_connection_module)

    original_sink = Application.get_env(:hueworks, :z2m_bootstrap_test_sink)

    Application.put_env(:hueworks, :z2m_bootstrap_tortoise_module, __MODULE__.TortoiseStub)

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_supervisor_module,
      __MODULE__.SupervisorStub
    )

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_connection_module,
      __MODULE__.ConnectionStub
    )

    Application.put_env(:hueworks, :z2m_bootstrap_test_sink, self())

    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    on_exit(fn ->
      Application.put_env(:hueworks, :z2m_bootstrap_tortoise_module, original_tortoise)

      Application.put_env(
        :hueworks,
        :z2m_bootstrap_tortoise_supervisor_module,
        original_supervisor
      )

      Application.put_env(
        :hueworks,
        :z2m_bootstrap_tortoise_connection_module,
        original_connection
      )

      Application.put_env(:hueworks, :z2m_bootstrap_test_sink, original_sink)
    end)

    :ok
  end

  test "bootstrap requests current z2m states and seeds control state" do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      Repo.insert!(%Bridge{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.80",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Kitchen Strip",
        source: :z2m,
        source_id: "kitchen_strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Kitchen Group",
        source: :z2m,
        source_id: "kitchen_group",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        metadata: %{"members" => ["kitchen_strip"]}
      })

    assert :ok == Z2M.run()

    assert_receive {:publish, client_id_a, topic_a, _payload_a, [qos: 0]}
    assert_receive {:publish, client_id_b, topic_b, _payload_b, [qos: 0]}

    assert client_id_a == client_id_b
    assert String.starts_with?(client_id_a, "hwz2mb#{bridge.id}_")

    assert Enum.sort([topic_a, topic_b]) == [
             "zigbee2mqtt/kitchen_group/get",
             "zigbee2mqtt/kitchen_strip/get"
           ]

    assert State.get(:light, light.id) == %{power: :off}
    assert State.get(:group, group.id) == %{power: :off}
  end

  defmodule TortoiseStub do
    def publish(client_id, topic, payload, opts) do
      send(
        Application.fetch_env!(:hueworks, :z2m_bootstrap_test_sink),
        {:publish, client_id, topic, payload, opts}
      )

      :ok
    end
  end

  defmodule SupervisorStub do
    def start_child(opts) do
      {handler_module, [owner]} = Keyword.fetch!(opts, :handler)
      sink = Application.fetch_env!(:hueworks, :z2m_bootstrap_test_sink)
      send(sink, {:start_child, opts})

      _ = handler_module

      worker =
        spawn(fn ->
          Process.sleep(10)

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "kitchen_strip"],
             Jason.encode!(%{"state" => "OFF"})}
          )

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "kitchen_group"],
             Jason.encode!(%{"state" => "OFF"})}
          )

          Process.sleep(:infinity)
        end)

      {:ok, worker}
    end
  end

  defmodule ConnectionStub do
    def connection(_client_id, _opts), do: {:ok, {:tcp, :socket}}
  end
end
