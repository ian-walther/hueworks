defmodule Hueworks.Subscription.CasetaEventStream.ConnectionTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light, Room}
  alias Hueworks.Subscription.CasetaEventStream.Connection

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    :ok
  end

  test "zone status frames update mapped Caseta lights" do
    room = Repo.insert!(%Room{name: "Living"})

    bridge =
      Repo.insert!(%Bridge{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.90",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "42",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    state = %{
      bridge: bridge,
      lights: %{light.source_id => light.id},
      buffer: ""
    }

    payload = %{
      "Body" => %{
        "ZoneStatus" => %{
          "Zone" => %{"href" => "/zone/42"},
          "Level" => 75
        }
      }
    }

    assert {:noreply, ^state} = Connection.handle_frame(Jason.encode!(payload), state)
    assert State.get(:light, light.id) == %{power: :on, brightness: 75}
  end

  test "button and invalid frames are ignored" do
    state = %{bridge: %Bridge{name: "Caseta", host: "10.0.0.91"}, lights: %{}, buffer: ""}

    button_payload = %{
      "Body" => %{
        "ButtonStatus" => %{
          "Button" => %{"href" => "/button/1"},
          "EventType" => "Press"
        }
      }
    }

    assert {:noreply, ^state} = Connection.handle_frame(Jason.encode!(button_payload), state)
    assert {:noreply, ^state} = Connection.handle_frame("{not-json", state)
  end
end
