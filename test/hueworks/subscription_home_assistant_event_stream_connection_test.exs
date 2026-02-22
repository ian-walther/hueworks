defmodule Hueworks.Subscription.HomeAssistantEventStream.ConnectionTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.HomeAssistantPayload
  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light, Room}
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
end
