defmodule Hueworks.PicosTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Picos
  alias Hueworks.Picos.Actions.ActionConfig
  alias Phoenix.PubSub
  alias Hueworks.Scenes
  alias Hueworks.Control.{DesiredState, State}
  alias Hueworks.Repo
  alias Hueworks.Schemas.PicoButton.ActionConfig, as: StoredActionConfig
  alias Hueworks.Schemas.{Group, GroupLight, Light, PicoButton, PicoDevice, Room}

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

    insert_bridge!(Map.merge(defaults, attrs))
  end

  defp insert_pico_button(attrs) do
    %PicoButton{}
    |> PicoButton.changeset(attrs)
    |> Repo.insert!()
  end

  test "button action config returns a typed runtime struct" do
    assert %ActionConfig{
             target_kind: :scene,
             target_id: 12,
             light_ids: [],
             room_id: 5
           } =
             ActionConfig.from_map(%{
               "target_kind" => "scene",
               "target_id" => "12",
               "room_id" => "5"
             })

    assert %ActionConfig{
             target_kind: :control_groups,
             target_id: nil,
             target_ids: ["group-9"],
             light_ids: [1, 2],
             room_id: nil
           } =
             ActionConfig.from_map(%{
               target_kind: :control_groups,
               target_ids: ["group-9"],
               light_ids: ["1", 2, "bad"]
             })

    assert %ActionConfig{
             target_kind: :control_groups,
             target_id: nil,
             target_ids: ["group-1", "group-2"],
             light_ids: [],
             room_id: nil
           } =
             ActionConfig.from_map(%{
               target_kind: :control_groups,
               target_ids: ["group-1", "group-2", "group-1"]
             })
  end

  test "stored pico action config normalizes to a compatible persisted map" do
    assert {:ok,
            %{
              "target_kind" => "scene",
              "target_id" => 12,
              "light_ids" => [1, 2],
              "room_id" => 5
            }} =
             StoredActionConfig.normalize(%{
               target_kind: :scene,
               target_id: "12",
               light_ids: ["1", 2, "bad"],
               room_id: "5"
             })

    assert {:ok,
            %{
              "target_kind" => "control_groups",
              "target_ids" => ["group-1", "group-2"]
            }} =
             StoredActionConfig.normalize(%{
               target_kind: :control_groups,
               target_ids: ["group-1", "group-2", "group-1"]
             })
  end

  test "pico button changeset normalizes action_config through the typed boundary" do
    changeset =
      PicoButton.changeset(%PicoButton{}, %{
        pico_device_id: 1,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        action_type: "activate_scene",
        action_config: %{target_kind: :scene, target_id: "12", room_id: "5"}
      })

    assert changeset.valid?

    assert %StoredActionConfig{
             target_kind: :scene,
             scene_id: 12,
             room_id: 5
           } = Ecto.Changeset.apply_changes(changeset).action_config
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

  test "sync_bridge_picos removes stale devices and stale button mappings" do
    bridge = insert_bridge(%{host: "10.0.0.54"})
    room = Repo.insert!(%Room{name: "Kitchen"})

    stale_device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "stale-device",
        name: "Stale Pico",
        hardware_profile: "2_button",
        enabled: true
      })

    active_device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-1",
        name: "Kitchen Pico",
        hardware_profile: "5_button",
        enabled: true
      })

    _stale_button =
      insert_pico_button(%{
        pico_device_id: active_device.id,
        source_id: "stale-button",
        button_number: 8,
        slot_index: 5,
        enabled: true
      })

    _active_button =
      insert_pico_button(%{
        pico_device_id: active_device.id,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        enabled: true
      })

    raw = %{
      lights: [],
      pico_buttons: [
        %{
          button_id: "1",
          button_number: 2,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: nil
        },
        %{
          button_id: "2",
          button_number: 4,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico",
          area_id: nil
        }
      ]
    }

    assert {:ok, [device]} = Picos.sync_bridge_picos(bridge, raw)
    assert device.source_id == "device-1"
    refute Repo.get(PicoDevice, stale_device.id)

    button_source_ids =
      Repo.all(from(pb in PicoButton, where: pb.pico_device_id == ^device.id, select: pb.source_id))
      |> Enum.sort()

    assert button_source_ids == ["1", "2"]
  end

  test "update_display_name normalizes blanks and sync preserves custom display_name" do
    bridge = insert_bridge(%{host: "10.0.0.541"})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        source_id: "device-1",
        name: "Kitchen Pico",
        hardware_profile: "5_button",
        enabled: true
      })

    assert {:ok, updated} = Picos.update_display_name(device, %{display_name: "  Accent Pico  "})
    assert updated.display_name == "Accent Pico"

    raw = %{
      lights: [],
      pico_buttons: [
        %{
          button_id: "1",
          button_number: 2,
          parent_device_id: "device-1",
          device_name: "Kitchen Pico Renamed Upstream",
          area_id: nil
        }
      ]
    }

    assert {:ok, [synced]} = Picos.sync_bridge_picos(bridge, raw)
    assert synced.name == "Kitchen Pico Renamed Upstream"
    assert synced.display_name == "Accent Pico"

    assert {:ok, cleared} = Picos.update_display_name(synced, %{display_name: "   "})
    assert cleared.display_name == nil
  end

  test "list_devices_for_bridge sorts by display name when present" do
    bridge = insert_bridge(%{host: "10.0.0.542"})

    Repo.insert!(%PicoDevice{
      bridge_id: bridge.id,
      source_id: "device-1",
      name: "Zulu Pico",
      display_name: "Alpha Pico",
      hardware_profile: "5_button",
      enabled: true
    })

    Repo.insert!(%PicoDevice{
      bridge_id: bridge.id,
      source_id: "device-2",
      name: "Bravo Pico",
      hardware_profile: "5_button",
      enabled: true
    })

    assert ["Alpha Pico", "Bravo Pico"] =
             Picos.list_devices_for_bridge(bridge.id)
             |> Enum.map(&Hueworks.Util.display_name/1)
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
      insert_pico_button(%{
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
               "target_kind" => "control_groups",
               "target_ids" => [control_group["id"]]
             })

    button =
      Repo.one!(
        from(pb in PicoButton, where: pb.pico_device_id == ^updated.id and pb.source_id == "1")
      )

    assert button.action_type == "toggle_any_on"
    assert %StoredActionConfig{
             target_kind: :control_groups,
             target_ids: control_group_ids
           } = PicoButton.action_config_struct(button)

    assert control_group_ids == [control_group["id"]]

    # The control group should expand only to room-local lights.
    assert Picos.button_binding_summary(button, Picos.get_device(updated.id)) == "Toggle Overhead"

    refute Enum.member?(control_group["group_ids"], other_group.id)
  end

  test "buttons can target multiple control groups" do
    bridge = insert_bridge(%{host: "10.0.0.519"})
    room = Repo.insert!(%Room{name: "Den"})

    overhead =
      Repo.insert!(%Light{
        name: "Overhead",
        source: :caseta,
        source_id: "91",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    lamp =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "92",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    overhead_group =
      Repo.insert!(%Group{
        name: "Overhead Group",
        source: :caseta,
        source_id: "group-91",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    lamp_group =
      Repo.insert!(%Group{
        name: "Lamp Group",
        source: :caseta,
        source_id: "group-92",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: overhead_group.id, light_id: overhead.id})
    Repo.insert!(%GroupLight{group_id: lamp_group.id, light_id: lamp.id})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-multi-group",
        name: "Den Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    assert {:ok, device} =
             Picos.save_control_group(device, %{
               "id" => "group-a",
               "name" => "Overhead",
               "group_ids" => [overhead_group.id],
               "light_ids" => []
             })

    assert {:ok, device} =
             Picos.save_control_group(device, %{
               "id" => "group-b",
               "name" => "Lamps",
               "group_ids" => [lamp_group.id],
               "light_ids" => []
             })

    assert {:ok, _button} =
             Picos.assign_button_binding(device, "1", %{
               "action" => "toggle",
               "target_kind" => "control_groups",
               "target_ids" => ["group-a", "group-b"]
             })

    button =
      Repo.one!(
        from(pb in PicoButton, where: pb.pico_device_id == ^device.id and pb.source_id == "1")
      )

    assert %StoredActionConfig{
             target_kind: :control_groups,
             target_ids: ["group-a", "group-b"]
           } = PicoButton.action_config_struct(button)

    assert Picos.button_binding_summary(button, Picos.get_device(device.id)) == "Toggle Overhead + Lamps"

    State.put(:light, overhead.id, %{power: :off})
    State.put(:light, lamp.id, %{power: :off})

    assert :handled = Picos.handle_button_press(bridge.id, "1")
    assert DesiredState.get(:light, overhead.id)[:power] == :on
    assert DesiredState.get(:light, lamp.id)[:power] == :on
  end

  test "scene bindings can be saved and button presses activate the selected scene" do
    bridge = insert_bridge(%{host: "10.0.0.515"})
    room = Repo.insert!(%Room{name: "Living Room"})

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "61",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "scene-device",
        name: "Scene Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, state} =
      Scenes.create_manual_light_state("Warm", %{"brightness" => "55", "temperature" => "3200"})

    {:ok, scene} = Scenes.create_scene(%{name: "Evening", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Lamps", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    assert {:ok, _button} =
             Picos.assign_button_binding(device, "1", %{
               "action" => "activate_scene",
               "target_kind" => "scene",
               "target_id" => Integer.to_string(scene.id)
             })

    button =
      Repo.one!(
        from(pb in PicoButton, where: pb.pico_device_id == ^device.id and pb.source_id == "1")
      )

    assert button.action_type == "activate_scene"
    assert %StoredActionConfig{target_kind: :scene, scene_id: scene_id} =
             PicoButton.action_config_struct(button)

    assert scene_id == scene.id

    assert Picos.button_binding_summary(button, Picos.get_device(device.id)) ==
             "Activate Scene Evening"

    assert :handled = Picos.handle_button_press(bridge.id, "1")
    assert ActiveScenes.get_for_room(room.id).scene_id == scene.id
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 55, kelvin: 3200}
  end

  test "control-group bindings execute on button press" do
    bridge = insert_bridge(%{host: "10.0.0.516"})
    room = Repo.insert!(%Room{name: "Kitchen"})

    overhead =
      Repo.insert!(%Light{
        name: "Overhead",
        source: :caseta,
        source_id: "81",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    lamp =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "82",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    group =
      Repo.insert!(%Group{
        name: "Kitchen Overhead",
        source: :caseta,
        source_id: "group-81",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: overhead.id})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-control-group",
        name: "Kitchen Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    assert {:ok, device} =
             Picos.save_control_group(device, %{
               "name" => "Overhead",
               "group_ids" => [group.id],
               "light_ids" => [lamp.id]
             })

    [control_group] = Picos.control_groups(device)

    assert {:ok, _button} =
             Picos.assign_button_binding(device, "1", %{
               "action" => "toggle",
               "target_kind" => "control_groups",
               "target_ids" => [control_group["id"]]
             })

    State.put(:light, overhead.id, %{power: :off})
    State.put(:light, lamp.id, %{power: :off})

    assert :handled = Picos.handle_button_press(bridge.id, "1")
    assert DesiredState.get(:light, overhead.id)[:power] == :on
    assert DesiredState.get(:light, lamp.id)[:power] == :on
  end

  test "persisted control-group bindings execute on button press" do
    bridge = insert_bridge(%{host: "10.0.0.5161"})
    room = Repo.insert!(%Room{name: "Kitchen"})

    overhead =
      Repo.insert!(%Light{
        name: "Overhead",
        source: :caseta,
        source_id: "81",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    lamp =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "82",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    group =
      Repo.insert!(%Group{
        name: "Kitchen Overhead",
        source: :caseta,
        source_id: "group-81",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: overhead.id})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "device-control-group-legacy",
        name: "Kitchen Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{
              "id" => "legacy-group",
              "name" => "Overhead",
              "group_ids" => [group.id],
              "light_ids" => [lamp.id]
            }
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "1",
      button_number: 2,
      slot_index: 0,
      action_type: "toggle_any_on",
      action_config: %{"target_kind" => "control_groups", "target_ids" => ["legacy-group"]},
      enabled: true
    })

    button =
      Repo.one!(
        from(pb in PicoButton, where: pb.pico_device_id == ^device.id and pb.source_id == "1")
      )

    assert %StoredActionConfig{
             target_kind: :control_groups,
             target_ids: ["legacy-group"]
           } = PicoButton.action_config_struct(button)

    State.put(:light, overhead.id, %{power: :off})
    State.put(:light, lamp.id, %{power: :off})

    assert :handled = Picos.handle_button_press(bridge.id, "1")
    assert DesiredState.get(:light, overhead.id)[:power] == :on
    assert DesiredState.get(:light, lamp.id)[:power] == :on
  end

  test "clone_device_config copies room scope, control groups, and bindings onto another pico" do
    bridge = insert_bridge(%{host: "10.0.0.511"})
    room = Repo.insert!(%Room{name: "Kitchen"})

    overhead =
      Repo.insert!(%Light{
        name: "Overhead",
        source: :caseta,
        source_id: "21",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    lamp =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "22",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    group =
      Repo.insert!(%Group{
        name: "Kitchen Overhead",
        source: :caseta,
        source_id: "group-21",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: overhead.id})

    {:ok, state} =
      Scenes.create_manual_light_state("Movie", %{"brightness" => "20", "temperature" => "2600"})

    {:ok, scene} = Scenes.create_scene(%{name: "Movie Time", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Room", light_ids: [overhead.id, lamp.id], light_state_id: to_string(state.id)}
      ])

    source =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "source-device",
        name: "Source Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    destination =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: nil,
        source_id: "destination-device",
        name: "Destination Pico",
        hardware_profile: "5_button",
        metadata: %{"detected_room_id" => nil, "room_override" => false}
      })

    for {device_id, source_id, button_number, slot_index} <- [
          {source.id, "s1", 2, 0},
          {source.id, "s2", 3, 1},
          {source.id, "s3", 4, 2},
          {destination.id, "d1", 2, 0},
          {destination.id, "d2", 3, 1},
          {destination.id, "d3", 4, 2}
        ] do
      insert_pico_button(%{
        pico_device_id: device_id,
        source_id: source_id,
        button_number: button_number,
        slot_index: slot_index,
        enabled: true
      })
    end

    assert {:ok, source} =
             Picos.save_control_group(source, %{
               "name" => "Overhead",
               "group_ids" => [group.id],
               "light_ids" => [lamp.id]
             })

    assert {:ok, source} =
             Picos.save_control_group(source, %{
               "name" => "Lamps",
               "group_ids" => [],
               "light_ids" => [lamp.id]
             })

    source_groups = Picos.control_groups(source)
    overhead_group = Enum.find(source_groups, &(&1["name"] == "Overhead"))
    lamps_group = Enum.find(source_groups, &(&1["name"] == "Lamps"))

    assert {:ok, _button} =
             Picos.assign_button_binding(source, "s1", %{
               "action" => "toggle",
               "target_kind" => "control_groups",
               "target_ids" => [overhead_group["id"]]
             })

    assert {:ok, _button} =
             Picos.assign_button_binding(source, "s2", %{
               "action" => "off",
               "target_kind" => "control_groups",
               "target_ids" => [overhead_group["id"], lamps_group["id"]]
             })

    assert {:ok, _button} =
             Picos.assign_button_binding(source, "s3", %{
               "action" => "activate_scene",
               "target_kind" => "scene",
               "target_id" => Integer.to_string(scene.id)
             })

    assert {:ok, cloned} = Picos.clone_device_config(destination, source)

    assert cloned.room_id == room.id
    assert Picos.room_override?(cloned)

    cloned_groups = Picos.control_groups(cloned)
    assert Enum.map(cloned_groups, & &1["name"]) == ["Lamps", "Overhead"]

    cloned_overhead_group = Enum.find(cloned_groups, &(&1["name"] == "Overhead"))
    cloned_lamps_group = Enum.find(cloned_groups, &(&1["name"] == "Lamps"))

    assert cloned_overhead_group["group_ids"] == [group.id]
    assert cloned_overhead_group["light_ids"] == [lamp.id]
    assert cloned_lamps_group["group_ids"] == []
    assert cloned_lamps_group["light_ids"] == [lamp.id]
    refute cloned_overhead_group["id"] == overhead_group["id"]
    refute cloned_lamps_group["id"] == lamps_group["id"]

    cloned_buttons =
      Repo.all(from(pb in PicoButton, where: pb.pico_device_id == ^cloned.id))
      |> Enum.sort_by(& &1.button_number)

    toggle_button = Enum.find(cloned_buttons, &(&1.button_number == 2))
    multi_group_button = Enum.find(cloned_buttons, &(&1.button_number == 3))
    scene_button = Enum.find(cloned_buttons, &(&1.button_number == 4))

    assert toggle_button.action_type == "toggle_any_on"
    assert %StoredActionConfig{
             target_kind: :control_groups,
             target_ids: toggle_group_ids,
             room_id: toggle_room_id
           } = PicoButton.action_config_struct(toggle_button)

    assert toggle_group_ids == [cloned_overhead_group["id"]]
    assert toggle_room_id == room.id

    assert multi_group_button.action_type == "turn_off"
    assert %StoredActionConfig{
             target_kind: :control_groups,
             target_ids: multi_group_ids,
             room_id: multi_group_room_id
           } = PicoButton.action_config_struct(multi_group_button)

    assert Enum.sort(multi_group_ids) ==
             Enum.sort([cloned_overhead_group["id"], cloned_lamps_group["id"]])

    assert multi_group_room_id == room.id

    assert scene_button.action_type == "activate_scene"
    assert %StoredActionConfig{
             target_kind: :scene,
             scene_id: scene_button_scene_id,
             room_id: scene_button_room_id
           } = PicoButton.action_config_struct(scene_button)

    assert scene_button_scene_id == scene.id
    assert scene_button_room_id == room.id
  end

  test "persisted scene bindings activate the selected scene" do
    bridge = insert_bridge(%{host: "10.0.0.5151"})
    room = Repo.insert!(%Room{name: "Living Room"})

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "61",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "scene-device-legacy",
        name: "Scene Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    {:ok, state} =
      Scenes.create_manual_light_state("Warm", %{"brightness" => "55", "temperature" => "3200"})

    {:ok, scene} = Scenes.create_scene(%{name: "Evening", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Lamps", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "1",
      button_number: 2,
      slot_index: 0,
      action_type: "activate_scene",
      action_config: %{"target_kind" => "scene", "target_id" => scene.id},
      enabled: true
    })

    button =
      Repo.one!(
        from(pb in PicoButton, where: pb.pico_device_id == ^device.id and pb.source_id == "1")
      )

    assert %StoredActionConfig{target_kind: :scene, scene_id: scene_id} =
             PicoButton.action_config_struct(button)

    assert scene_id == scene.id

    assert :handled = Picos.handle_button_press(bridge.id, "1")
    assert ActiveScenes.get_for_room(room.id).scene_id == scene.id
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 55, kelvin: 3200}
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

  test "clear_device_config removes control groups and bindings and resets room override" do
    bridge = insert_bridge(%{host: "10.0.0.543"})
    auto_room = Repo.insert!(%Room{name: "Auto Room"})
    manual_room = Repo.insert!(%Room{name: "Manual Room"})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: manual_room.id,
        source_id: "device-clear-config",
        name: "Kitchen Pico",
        hardware_profile: "5_button",
        metadata: %{
          "detected_room_id" => auto_room.id,
          "room_override" => true,
          "control_groups" => [
            %{"id" => "accent", "name" => "Accent", "group_ids" => [], "light_ids" => []}
          ],
          "preset" => "overhead_lamps_all_toggle",
          "primary" => %{"group_ids" => [], "light_ids" => []},
          "secondary" => %{"group_ids" => [], "light_ids" => []}
        }
      })

    button =
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        action_type: "toggle_any_on",
        action_config: %{"target_kind" => "control_groups", "target_ids" => ["accent"]},
        enabled: true,
        metadata: %{"preset" => "overhead_lamps_all_toggle"}
      })

    assert {:ok, cleared} = Picos.clear_device_config(device)
    assert cleared.room_id == auto_room.id
    refute Picos.room_override?(cleared)
    assert Picos.control_groups(cleared) == []
    refute Map.has_key?(cleared.metadata || %{}, "preset")
    refute Map.has_key?(cleared.metadata || %{}, "primary")
    refute Map.has_key?(cleared.metadata || %{}, "secondary")

    reloaded_button = Repo.get!(PicoButton, button.id)
    assert reloaded_button.action_type == nil
    assert PicoButton.action_config_struct(reloaded_button).target_kind == nil
    refute Map.has_key?(reloaded_button.metadata || %{}, "preset")
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
      insert_pico_button(%{
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
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        action_type: "toggle_any_on",
        action_config: %{
          "target_kind" => "control_groups",
          "target_ids" => ["accent"],
          "room_id" => room.id
        },
        enabled: true
      })

    State.put(:light, light.id, %{power: :on})
    DesiredState.put(:light, light.id, %{power: :off})

    assert :handled = Picos.handle_button_press(bridge.id, "1")
    assert DesiredState.get(:light, light.id)[:power] == :on
  end
end
