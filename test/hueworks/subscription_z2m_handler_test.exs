defmodule Hueworks.Subscription.Z2MHandlerTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.HomeAssistantPayload
  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, Room}
  alias Hueworks.Subscription.Z2MEventStream.Connection.Handler

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    :ok
  end

  test "handler maps device and group MQTT events into control state" do
    room = Repo.insert!(%Room{name: "Main"})

    bridge =
      Repo.insert!(%Bridge{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.70",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    light_a =
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

    light_b =
      Repo.insert!(%Light{
        name: "Ceiling",
        source: :z2m,
        source_id: "kitchen_ceiling",
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
        metadata: %{"members" => ["kitchen_strip", "kitchen_ceiling"]}
      })

    {:ok, state} = Handler.init([bridge.id, "zigbee2mqtt"])

    {:ok, state} =
      Handler.handle_message(
        ["zigbee2mqtt", "kitchen_strip"],
        Jason.encode!(%{"state" => "ON", "brightness" => 127, "color_temp" => 250}),
        state
      )

    assert State.get(:light, light_a.id) == %{power: :on, brightness: 50, kelvin: 4000}

    {:ok, _state} =
      Handler.handle_message(
        ["zigbee2mqtt", "kitchen_group"],
        Jason.encode!(%{"state" => "OFF"}),
        state
      )

    assert State.get(:group, group.id) == %{power: :off}
    assert State.get(:light, light_a.id).power == :off
    assert State.get(:light, light_b.id).power == :off
  end

  test "handler ignores bridge and set topics" do
    bridge =
      Repo.insert!(%Bridge{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.71",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    {:ok, state} = Handler.init([bridge.id, "zigbee2mqtt"])

    assert {:ok, ^state} =
             Handler.handle_message(
               ["zigbee2mqtt", "bridge", "state"],
               Jason.encode!(%{"state" => "online"}),
               state
             )

    assert {:ok, ^state} =
             Handler.handle_message(
               ["zigbee2mqtt", "kitchen_strip", "set"],
               Jason.encode!(%{"state" => "ON"}),
               state
             )
  end

  test "handler uses extended color payload mapping for low kelvin updates" do
    room = Repo.insert!(%Room{name: "Extended"})

    bridge =
      Repo.insert!(%Bridge{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.72",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Cabinet",
        source: :z2m,
        source_id: "cabinet_strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6329,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    {x, y} = HomeAssistantPayload.extended_xy(2000)

    {:ok, state} = Handler.init([bridge.id, "zigbee2mqtt"])

    {:ok, _state} =
      Handler.handle_message(
        ["zigbee2mqtt", "cabinet_strip"],
        Jason.encode!(%{
          "state" => "ON",
          "color" => %{"x" => x, "y" => y},
          "color_temp" => 437
        }),
        state
      )

    assert State.get(:light, light.id) == %{power: :on, kelvin: 2000}
  end
end
