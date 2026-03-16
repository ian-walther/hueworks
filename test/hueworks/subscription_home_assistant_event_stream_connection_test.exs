defmodule Hueworks.Subscription.HomeAssistantEventStream.ConnectionTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.HomeAssistantPayload
  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, Room}
  alias Hueworks.Subscription.HomeAssistantEventStream.Connection

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    :ok
  end

  test "event handler maps extended xy HA updates to low kelvin values" do
    room = Repo.insert!(%Room{name: "Living"})

    bridge =
      Repo.insert!(%Bridge{
        type: :ha,
        name: "HA",
        host: "10.0.0.80",
        credentials: %{"token" => "token"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Cabinet",
        source: :ha,
        source_id: "light.cabinet",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    {x, y} = HomeAssistantPayload.extended_xy(2000)

    state = %{
      lights: %{light.source_id => light},
      groups: %{},
      group_members: %{}
    }

    payload = %{
      "type" => "event",
      "event" => %{
        "data" => %{
          "entity_id" => light.source_id,
          "new_state" => %{
            "state" => "on",
            "attributes" => %{
              "xy_color" => [x, y],
              "color_temp" => 437
            }
          }
        }
      }
    }

    assert {:ok, _state} = Connection.handle_frame({:text, Jason.encode!(payload)}, state)

    assert State.get(:light, light.id) == %{power: :on, kelvin: 2000}
  end

  test "auth_required replies with auth payload and auth_ok subscribes to state_changed" do
    state = %{
      bridge: %Bridge{name: "HA", host: "10.0.0.80"},
      token: "token-123",
      next_id: 1,
      subscribed: false,
      lights: %{},
      groups: %{},
      group_members: %{}
    }

    assert {:reply, {:text, auth_json}, ^state} =
             Connection.handle_frame({:text, Jason.encode!(%{"type" => "auth_required"})}, state)

    assert Jason.decode!(auth_json) == %{"type" => "auth", "access_token" => "token-123"}

    assert {:reply, {:text, subscribe_json}, subscribed_state} =
             Connection.handle_frame({:text, Jason.encode!(%{"type" => "auth_ok"})}, state)

    assert Jason.decode!(subscribe_json) == %{
             "id" => 1,
             "type" => "subscribe_events",
             "event_type" => "state_changed"
           }

    assert subscribed_state.subscribed == true
    assert subscribed_state.next_id == 2
  end

  test "state_changed group events fan out state to member lights" do
    room = Repo.insert!(%Room{name: "Living"})

    bridge =
      Repo.insert!(%Bridge{
        type: :ha,
        name: "HA",
        host: "10.0.0.81",
        credentials: %{"token" => "token"},
        enabled: true
      })

    light_a =
      Repo.insert!(%Light{
        name: "Lamp A",
        source: :ha,
        source_id: "light.a",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_b =
      Repo.insert!(%Light{
        name: "Lamp B",
        source: :ha,
        source_id: "light.b",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Living Group",
        source: :ha,
        source_id: "light.living_group",
        bridge_id: bridge.id,
        room_id: room.id,
        metadata: %{"members" => [light_a.source_id, light_b.source_id]}
      })

    state = %{
      bridge: bridge,
      token: "token",
      next_id: 1,
      subscribed: true,
      lights: %{light_a.source_id => light_a, light_b.source_id => light_b},
      groups: %{group.source_id => group},
      group_members: %{group.source_id => [light_a.id, light_b.id]}
    }

    payload = %{
      "type" => "event",
      "event" => %{
        "data" => %{
          "entity_id" => group.source_id,
          "new_state" => %{
            "state" => "on",
            "attributes" => %{
              "brightness" => 128,
              "color_temp" => 400
            }
          }
        }
      }
    }

    assert {:ok, ^state} = Connection.handle_frame({:text, Jason.encode!(payload)}, state)

    assert State.get(:group, group.id) == %{power: :on, brightness: 50, kelvin: 2500}
    assert State.get(:light, light_a.id) == %{power: :on, brightness: 50, kelvin: 2500}
    assert State.get(:light, light_b.id) == %{power: :on, brightness: 50, kelvin: 2500}
  end

  test "invalid json frames are ignored" do
    state = %{
      bridge: %Bridge{name: "HA", host: "10.0.0.80"},
      token: "token",
      next_id: 1,
      subscribed: false,
      lights: %{},
      groups: %{},
      group_members: %{}
    }

    assert {:ok, ^state} = Connection.handle_frame({:text, "{not-json"}, state)
  end
end
