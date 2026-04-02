defmodule Hueworks.PicosTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Picos
  alias Phoenix.PubSub
  alias Hueworks.Control.{DesiredState, State}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, PicoButton, PicoDevice, Room}

  defp insert_bridge(attrs \\ %{}) do
    defaults = %{
      type: :caseta,
      name: "Caseta",
      host: "10.0.0.50",
      credentials: %{
        "cert_path" => "/credentials/caseta.crt",
        "key_path" => "/credentials/caseta.key",
        "cacert_path" => "/credentials/caseta-ca.crt"
      },
      enabled: true,
      import_complete: true
    }

    Repo.insert!(struct(Bridge, Map.merge(defaults, attrs)))
  end

  test "sync_bridge_picos derives room and button layout from Caseta raw data" do
    bridge = insert_bridge()
    room = Repo.insert!(%Room{name: "Kitchen"})

    _light =
      Repo.insert!(%Light{
        name: "Kitchen Overhead",
        source: :caseta,
        source_id: "42",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    raw = %{
      lights: [
        %{zone_id: "42", area_id: "100", name: "Kitchen / Overhead"}
      ],
      pico_buttons: [
        %{
          button_id: "1",
          button_number: 2,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "2",
          button_number: 4,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "3",
          button_number: 3,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "4",
          button_number: 5,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "5",
          button_number: 6,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        }
      ]
    }

    assert {:ok, [device]} = Picos.sync_bridge_picos(bridge, raw)

    assert device.source_id == "device-1"
    assert device.room_id == room.id
    assert device.hardware_profile == "5_button"
    assert Enum.map(device.buttons, & &1.slot_index) == [0, 1, 2, 3, 4]
    assert Enum.map(device.buttons, & &1.button_number) == [2, 3, 4, 5, 6]
  end

  test "control groups can be saved and buttons can target them" do
    bridge = insert_bridge(%{host: "10.0.0.51"})
    room = Repo.insert!(%Room{name: "Den"})
    other_room = Repo.insert!(%Room{name: "Other"})

    overhead_a =
      Repo.insert!(%Light{
        name: "Overhead A",
        source: :caseta,
        source_id: "10",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    overhead_b =
      Repo.insert!(%Light{
        name: "Overhead B",
        source: :caseta,
        source_id: "11",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    lamp =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "12",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    _other =
      Repo.insert!(%Light{
        name: "Other",
        source: :caseta,
        source_id: "13",
        bridge_id: bridge.id,
        room_id: other_room.id,
        enabled: true
      })

    overhead_group =
      Repo.insert!(%Group{
        name: "Overhead",
        source: :caseta,
        source_id: "group-1",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    other_group =
      Repo.insert!(%Group{
        name: "Other Group",
        source: :caseta,
        source_id: "group-2",
        bridge_id: bridge.id,
        room_id: other_room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: overhead_group.id, light_id: overhead_a.id})
    Repo.insert!(%GroupLight{group_id: overhead_group.id, light_id: overhead_b.id})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-1",
        name: "Den Pico",
        hardware_profile: "5_button"
      })

    for {source_id, button_number, slot_index} <- [
          {"1", 2, 0},
          {"2", 3, 1},
          {"3", 4, 2},
          {"4", 5, 3},
          {"5", 6, 4}
        ] do
      Repo.insert!(%PicoButton{
        pico_device_id: device.id,
        source_id: source_id,
        button_number: button_number,
        slot_index: slot_index
      })
    end

    assert {:error, :invalid_targets} =
             Picos.save_control_group(device, %{
               "name" => "Overhead",
               "group_ids" => [overhead_group.id, other_group.id],
               "light_ids" => []
             })

    assert {:ok, updated} =
             Picos.save_control_group(device, %{
               "name" => "Overhead",
               "group_ids" => [overhead_group.id],
               "light_ids" => []
             })

    [control_group] = Picos.control_groups(updated)
    assert control_group["name"] == "Overhead"
    assert control_group["group_ids"] == [overhead_group.id]

    assert {:ok, updated} =
             Picos.save_control_group(updated, %{
               "id" => control_group["id"],
               "name" => "Overhead",
               "group_ids" => [overhead_group.id],
               "light_ids" => [lamp.id]
             })

    [control_group] = Picos.control_groups(updated)
    assert control_group["group_ids"] == [overhead_group.id]
    assert control_group["light_ids"] == [lamp.id]

    assert {:ok, _button} =
             Picos.assign_button_binding(updated, "1", %{
               "action" => "toggle",
               "target_kind" => "control_group",
               "target_id" => control_group["id"]
             })

    button =
      Repo.one!(
        from(pb in PicoButton, where: pb.pico_device_id == ^updated.id and pb.source_id == "1")
      )

    assert button.action_type == "toggle_any_on"
    assert button.action_config["target_kind"] == "control_group"
    assert button.action_config["target_id"] == control_group["id"]

    # The control group should expand only to room-local lights.
    assert Picos.button_binding_summary(button, Picos.get_device(updated.id)) == "Toggle Overhead"

    refute Enum.member?(control_group["group_ids"], other_group.id)
  end

  test "manual room override survives sync and can be cleared back to auto-detected room" do
    bridge = insert_bridge(%{host: "10.0.0.52"})
    auto_room = Repo.insert!(%Room{name: "Auto Room"})
    manual_room = Repo.insert!(%Room{name: "Manual Room"})

    _light =
      Repo.insert!(%Light{
        name: "Auto Room Light",
        source: :caseta,
        source_id: "42",
        bridge_id: bridge.id,
        room_id: auto_room.id,
        enabled: true
      })

    raw = %{
      lights: [
        %{zone_id: "42", area_id: "100", name: "Auto Room / Overhead"}
      ],
      pico_buttons: [
        %{
          button_id: "1",
          button_number: 2,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "2",
          button_number: 3,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "3",
          button_number: 4,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "4",
          button_number: 5,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        },
        %{
          button_id: "5",
          button_number: 6,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: "100"
        }
      ]
    }

    assert {:ok, [device]} = Picos.sync_bridge_picos(bridge, raw)
    assert device.room_id == auto_room.id
    refute Picos.room_override?(device)

    assert {:ok, overridden} = Picos.set_device_room(device, manual_room.id)
    assert overridden.room_id == manual_room.id
    assert Picos.room_override?(overridden)

    assert {:ok, [synced]} = Picos.sync_bridge_picos(bridge, raw)
    assert synced.room_id == manual_room.id
    assert Picos.room_override?(synced)

    assert {:ok, reset} = Picos.set_device_room(synced, nil)
    assert reset.room_id == auto_room.id
    refute Picos.room_override?(reset)
  end

  test "unbound button presses still broadcast for learning" do
    bridge = insert_bridge(%{host: "10.0.0.53"})
    room = Repo.insert!(%Room{name: "Kitchen"})
    PubSub.subscribe(Hueworks.PubSub, Picos.topic())

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-1",
        name: "Kitchen Pico",
        hardware_profile: "5_button"
      })

    button =
      Repo.insert!(%PicoButton{
        pico_device_id: device.id,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        action_type: nil,
        action_config: %{},
        enabled: true
      })

    device_id = device.id

    assert :ignored = Picos.handle_button_press(bridge.id, "1")
    assert_received {:pico_button_press, ^device_id, "1"}

    reloaded = Repo.get!(PicoButton, button.id)
    refute is_nil(reloaded.last_pressed_at)

    assert {:ok, cleared} = Picos.clear_button_binding(reloaded)
    assert cleared.enabled == true
  end

  test "toggle decisions prefer desired state over stale physical state" do
    bridge = insert_bridge(%{host: "10.0.0.54"})
    room = Repo.insert!(%Room{name: "Kitchen"})

    light =
      Repo.insert!(%Light{
        name: "Accent",
        source: :caseta,
        source_id: "14",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-1",
        name: "Kitchen Pico",
        hardware_profile: "5_button",
        metadata: %{
          "control_groups" => [
            %{
              "id" => "accent",
              "name" => "Accent",
              "group_ids" => [],
              "light_ids" => [light.id]
            }
          ]
        }
      })

    _button =
      Repo.insert!(%PicoButton{
        pico_device_id: device.id,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        action_type: "toggle_any_on",
        action_config: %{"target_kind" => "all_groups", "room_id" => room.id},
        enabled: true
      })

    State.put(:light, light.id, %{power: :on})
    DesiredState.put(:light, light.id, %{power: :off})

    assert :handled = Picos.handle_button_press(bridge.id, "1")
    assert DesiredState.get(:light, light.id)[:power] == :on
  end
end
