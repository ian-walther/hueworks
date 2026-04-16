defmodule Hueworks.Control.Z2MDispatchTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, Executor, Group, Light, Planner}
  alias Hueworks.Repo
  alias Hueworks.Schemas.Group, as: GroupSchema
  alias Hueworks.Schemas.Light, as: LightSchema
  alias Hueworks.Schemas.Room

  setup do
    original_tortoise = Application.get_env(:hueworks, :z2m_tortoise_module)
    original_supervisor = Application.get_env(:hueworks, :z2m_tortoise_supervisor_module)
    original_connection = Application.get_env(:hueworks, :z2m_tortoise_connection_module)
    original_sink = Application.get_env(:hueworks, :z2m_publish_sink)

    Application.put_env(:hueworks, :z2m_tortoise_module, __MODULE__.TortoiseStub)
    Application.put_env(:hueworks, :z2m_tortoise_supervisor_module, __MODULE__.SupervisorStub)
    Application.put_env(:hueworks, :z2m_tortoise_connection_module, __MODULE__.ConnectionStub)
    Application.put_env(:hueworks, :z2m_publish_sink, self())

    on_exit(fn ->
      restore_app_env(:hueworks, :z2m_tortoise_module, original_tortoise)
      restore_app_env(:hueworks, :z2m_tortoise_supervisor_module, original_supervisor)
      restore_app_env(:hueworks, :z2m_tortoise_connection_module, original_connection)
      restore_app_env(:hueworks, :z2m_publish_sink, original_sink)
    end)

    :ok
  end

  test "Light.set_state publishes z2m set topic" do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.60",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    light =
      Repo.insert!(%LightSchema{
        name: "Strip",
        source: :z2m,
        source_id: "kitchen_strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    assert :ok == Light.set_state(light, %{power: :on, brightness: 50, kelvin: 4000})

    assert_receive {:published, client_id, "zigbee2mqtt/kitchen_strip/set", payload, [qos: 0]}
    assert client_id == "hwz2mc#{bridge.id}-test"

    decoded = Jason.decode!(payload)
    assert decoded["state"] == "ON"
    assert decoded["brightness"] == 127
    assert decoded["color_temp"] == 250
  end

  test "Group.set_state publishes z2m set topic" do
    room = Repo.insert!(%Room{name: "Main"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.61",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    group =
      Repo.insert!(%GroupSchema{
        name: "Main Group",
        source: :z2m,
        source_id: "main_group",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    assert :ok == Group.set_state(group, %{power: :on, brightness: 30})

    assert_receive {:published, _client_id, "zigbee2mqtt/main_group/set", payload, [qos: 0]}

    decoded = Jason.decode!(payload)
    assert decoded["state"] == "ON"
    assert decoded["brightness"] == 76
  end

  test "planner/executor publishes color-mode payload for extended low kelvin on z2m light" do
    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    Application.put_env(:hueworks, :control_executor_enabled, true)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
    end)

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      :ets.delete_all_objects(:hueworks_desired_state)
    end

    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.62",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    light =
      Repo.insert!(%LightSchema{
        name: "Strip",
        source: :z2m,
        source_id: "kitchen_strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        extended_kelvin_range: true,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    desired = %{power: :on, kelvin: 2000}
    DesiredState.put(:light, light.id, desired)
    diff = %{{:light, light.id} => desired}

    plan = Planner.plan_room(room.id, diff)
    light_id = light.id
    assert [%{type: :light, id: ^light_id, desired: %{kelvin: 2000}}] = plan

    server = {:global, {:z2m_extended_executor, self()}}
    {:ok, _pid} = start_supervised({Executor, name: server})

    assert :ok == Executor.enqueue(plan, server: server)
    _ = Executor.tick(server, force: true)

    assert_receive {:published, _client_id, "zigbee2mqtt/kitchen_strip/set", payload, [qos: 0]}

    decoded = Jason.decode!(payload)
    assert decoded["state"] == "ON"
    assert is_map(decoded["color"])
    assert is_number(decoded["color"]["x"])
    assert is_number(decoded["color"]["y"])
    refute Map.has_key?(decoded, "color_temp")
  end

  defmodule TortoiseStub do
    def publish(client_id, topic, payload, opts) do
      send(
        Application.fetch_env!(:hueworks, :z2m_publish_sink),
        {:published, client_id, topic, payload, opts}
      )

      :ok
    end
  end

  defmodule SupervisorStub do
    def start_child(_opts), do: {:ok, self()}
  end

  defmodule ConnectionStub do
    def connection(_client_id, _opts), do: {:ok, {:tcp, :socket}}
  end
end
