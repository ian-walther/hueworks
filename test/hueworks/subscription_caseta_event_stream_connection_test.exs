defmodule Hueworks.Subscription.CasetaEventStream.ConnectionTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State
  alias Hueworks.Control.DesiredState
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, PicoButton, PicoDevice, Room}
  alias Hueworks.Subscription.CasetaEventStream.Connection

  defp insert_pico_button(attrs) do
    %PicoButton{}
    |> PicoButton.changeset(attrs)
    |> Repo.insert!()
  end

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    :ok
  end

  test "zone status frames update mapped Caseta lights" do
    room = Repo.insert!(%Room{name: "Living"})

    bridge =
      insert_bridge!(%{
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

  test "button press frames trigger configured Pico button actions" do
    room = Repo.insert!(%Room{name: "Living"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.91",
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
        source_id: "52",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-1",
        name: "Living Pico",
        hardware_profile: "5_button"
      })

    _button =
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        action_type: "turn_on",
        action_config: %{"light_ids" => [light.id]}
      })

    state = %{bridge: bridge, lights: %{}, buffer: ""}

    button_payload = %{
      "Body" => %{
        "ButtonStatus" => %{
          "Button" => %{"href" => "/button/1"},
          "EventType" => "Press"
        }
      }
    }

    assert {:noreply, ^state} = Connection.handle_frame(Jason.encode!(button_payload), state)
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 100, kelvin: 3000}
    assert {:noreply, ^state} = Connection.handle_frame("{not-json", state)
  end

  test "nested button event frames trigger configured Pico button actions" do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.92",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Accent",
        source: :caseta,
        source_id: "62",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-2",
        name: "Kitchen Accent Pico",
        hardware_profile: "5_button"
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "101",
      button_number: 2,
      slot_index: 0,
      action_type: "turn_on",
      action_config: %{"light_ids" => [light.id]}
    })

    state = %{bridge: bridge, lights: %{}, pico_button_ids: ["101"], buffer: ""}

    button_payload = %{
      "Header" => %{
        "Url" => "/button/101/status/event",
        "MessageBodyType" => "OneButtonStatusEvent"
      },
      "Body" => %{
        "ButtonStatus" => %{
          "Button" => %{"href" => "/button/101"},
          "ButtonEvent" => %{"EventType" => "Press"}
        }
      }
    }

    assert {:noreply, ^state} = Connection.handle_frame(Jason.encode!(button_payload), state)
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 100, kelvin: 3000}
  end
end
