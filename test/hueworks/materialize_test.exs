defmodule Hueworks.Import.MaterializeTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.{Materialize, NormalizeFromDb, Plan, ReimportPlan}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, Room}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "materializes rooms, lights, groups, and memberships while preserving edits" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.2",
        credentials: %{"token" => "token"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    office_room = Repo.insert!(%Room{name: "Office"})

    existing_light =
      %Light{}
      |> Light.changeset(%{
        name: "Old Lamp",
        display_name: "Custom Lamp",
        source: :ha,
        source_id: "light.office_lamp",
        bridge_id: bridge.id,
        room_id: office_room.id,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        enabled: false
      })
      |> Repo.insert!()

    existing_group =
      %Group{}
      |> Group.changeset(%{
        name: "Old Group",
        display_name: "Custom Group",
        source: :ha,
        source_id: "light.office_group",
        bridge_id: bridge.id,
        room_id: office_room.id,
        enabled: false
      })
      |> Repo.insert!()

    normalized = load_fixture("materialize_ha.json")

    :ok = Materialize.materialize(bridge, normalized, Plan.build_default(normalized))

    room = Repo.get_by!(Room, name: "Office")

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.office_lamp")
    assert light.room_id == room.id
    assert light.display_name == "Custom Lamp"
    refute light.enabled
    assert light.actual_min_kelvin == 2700
    assert light.actual_max_kelvin == 6500
    assert light.reported_min_kelvin == 2000
    assert light.reported_max_kelvin == 6500

    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "light.office_group")
    assert group.room_id == room.id
    assert group.display_name == "Custom Group"
    refute group.enabled

    assert Repo.get_by(GroupLight, group_id: group.id, light_id: light.id)
    assert Repo.get_by(Light, id: existing_light.id)
    assert Repo.get_by(Group, id: existing_group.id)

    studio_group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "light.studio_group")
    assert studio_group.room_id == nil
  end

  test "materializes Hue metadata and bridge_host" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.9",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = load_fixture("materialize_hue.json")

    :ok = Materialize.materialize(bridge, normalized)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "1")
    assert light.metadata["bridge_host"] == "10.0.0.9"

    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "2")
    assert group.metadata["bridge_host"] == "10.0.0.9"
  end

  test "reimport preserve action does not move existing lights to bridge-reported rooms" do
    bridge = insert_bridge()
    original_room = insert_room("HueWorks Room")
    imported_room = insert_room("Bridge Room")

    light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        room_id: original_room.id,
        external_id: "ha:light.office_lamp"
      })

    insert_group(bridge, %{
      source_id: "light.office_group",
      room_id: original_room.id,
      external_id: "ha:light.office_group"
    })

    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{"office" => %{"action" => "merge", "target_room_id" => "#{imported_room.id}"}},
      lights: %{"light.office_lamp" => true, "light.studio_a" => false, "light.studio_b" => false},
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.reload!(light).room_id == original_room.id
  end

  test "reimport preserve action does not move existing groups to bridge-reported rooms" do
    bridge = insert_bridge()
    original_room = insert_room("HueWorks Group Room")
    imported_room = insert_room("Bridge Group Room")

    light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        room_id: original_room.id,
        external_id: "ha:light.office_lamp"
      })

    group =
      insert_group(bridge, %{
        source_id: "light.office_group",
        room_id: original_room.id,
        external_id: "ha:light.office_group"
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})

    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{"office" => %{"action" => "merge", "target_room_id" => "#{imported_room.id}"}},
      lights: %{"light.office_lamp" => true, "light.studio_a" => false, "light.studio_b" => false},
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.reload!(group).room_id == original_room.id
  end

  test "reimport preserve action refreshes existing imported capabilities without touching overrides" do
    bridge = insert_bridge()

    light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        supports_color: true,
        supports_temp: false,
        reported_min_kelvin: 2700,
        reported_max_kelvin: 5000,
        actual_min_kelvin: 2600,
        actual_max_kelvin: 5200,
        extended_min_kelvin: 2000,
        extended_kelvin_range: true
      })

    insert_group(bridge, %{source_id: "light.office_group"})

    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{},
      lights: %{"light.office_lamp" => true, "light.studio_a" => false, "light.studio_b" => false},
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    light = Repo.reload!(light)
    refute light.supports_color
    assert light.supports_temp
    assert light.reported_min_kelvin == 2000
    assert light.reported_max_kelvin == 6500
    assert light.actual_min_kelvin == 2600
    assert light.actual_max_kelvin == 5200
    assert light.extended_min_kelvin == 2000
    assert light.extended_kelvin_range
  end

  test "reimport preserve action refreshes source names without touching display names" do
    bridge = insert_bridge()

    light =
      insert_light(bridge, %{
        name: "HueWorks Light Name",
        display_name: "Pinned Light Name",
        source_id: "light.office_lamp"
      })

    group =
      insert_group(bridge, %{
        name: "HueWorks Group Name",
        display_name: "Pinned Group Name",
        source_id: "light.office_group"
      })

    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{},
      lights: %{"light.office_lamp" => true, "light.studio_a" => false, "light.studio_b" => false},
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    light = Repo.reload!(light)
    group = Repo.reload!(group)

    assert light.name == "Office Lamp"
    assert light.display_name == "Pinned Light Name"
    assert group.name == "Office Group"
    assert group.display_name == "Pinned Group Name"
  end

  test "reimport preserve action refreshes existing external ids" do
    bridge = insert_bridge()

    light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        external_id: "existing-light-external"
      })

    group =
      insert_group(bridge, %{
        source_id: "light.office_group",
        external_id: "existing-group-external"
      })

    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{},
      lights: %{"light.office_lamp" => true, "light.studio_a" => false, "light.studio_b" => false},
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.reload!(light).external_id == "ha-light-1"
    assert Repo.reload!(group).external_id == "light.office_group"
  end

  test "reimport preserve action refreshes existing imported metadata" do
    bridge = insert_bridge()

    light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        metadata: %{"unique_id" => "existing-light"}
      })

    group =
      insert_group(bridge, %{
        source_id: "light.office_group",
        metadata: %{"members" => []}
      })

    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{},
      lights: %{"light.office_lamp" => true, "light.studio_a" => false, "light.studio_b" => false},
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    light = Repo.reload!(light)

    assert light.metadata == %{
             "bridge_host" => "10.0.0.2",
             "identifiers" => %{"mac" => "00:aa:bb:cc:dd:ee"},
             "unique_id" => "ha-light-1"
           }

    group = Repo.reload!(group)

    assert group.metadata == %{
             "bridge_host" => "10.0.0.2",
             "members" => ["light.office_lamp"]
           }
  end

  test "reimport preserve action refreshes existing normalized snapshots" do
    bridge = insert_bridge()

    light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        normalized_json: %{
          "source_id" => "light.office_lamp",
          "metadata" => %{"unique_id" => "existing-light"}
        }
      })

    group =
      insert_group(bridge, %{
        source_id: "light.office_group",
        normalized_json: %{"source_id" => "light.office_group", "metadata" => %{"members" => []}}
      })

    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{},
      lights: %{"light.office_lamp" => true, "light.studio_a" => false, "light.studio_b" => false},
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    light = Repo.reload!(light)

    assert light.normalized_json["source_id"] == "light.office_lamp"
    assert light.normalized_json["name"] == "Office Lamp"
    assert light.normalized_json["metadata"] == %{"unique_id" => "ha-light-1"}
    assert light.normalized_json["identifiers"] == %{"mac" => "00:aa:bb:cc:dd:ee"}

    group = Repo.reload!(group)

    assert group.normalized_json["source_id"] == "light.office_group"
    assert group.normalized_json["name"] == "Office Group"
    assert group.normalized_json["metadata"] == %{"members" => ["light.office_lamp"]}
  end

  test "reimport preserve action refreshes bridge-reported group memberships" do
    bridge = insert_bridge()

    existing_light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        external_id: "ha:light.office_lamp"
      })

    extra_existing_light =
      insert_light(bridge, %{
        source_id: "light.studio_a",
        external_id: "ha:light.studio_a"
      })

    group =
      insert_group(bridge, %{
        source_id: "light.office_group",
        external_id: "ha:light.office_group"
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: existing_light.id})

    normalized =
      load_fixture("materialize_ha.json")
      |> put_in(
        ["memberships", "group_lights"],
        [
          %{"group_source_id" => "light.office_group", "light_source_id" => "light.office_lamp"},
          %{"group_source_id" => "light.office_group", "light_source_id" => "light.studio_a"}
        ]
      )

    plan = %{
      rooms: %{},
      lights: %{
        "light.office_lamp" => true,
        "light.studio_a" => true,
        "light.studio_b" => false
      },
      groups: %{"light.office_group" => true, "light.studio_group" => false}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.get_by(GroupLight, group_id: group.id, light_id: existing_light.id)
    assert Repo.get_by(GroupLight, group_id: group.id, light_id: extra_existing_light.id)
  end

  test "reimport preserve action clears bridge-reported group memberships when upstream is empty" do
    bridge = insert_bridge()

    existing_light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        external_id: "ha:light.office_lamp"
      })

    group =
      insert_group(bridge, %{
        source_id: "light.office_group",
        external_id: "ha:light.office_group"
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: existing_light.id})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.office_group",
          name: "Office Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"members" => []}
        }
      ],
      memberships: %{group_lights: []}
    }

    plan = %{
      rooms: %{},
      lights: %{"light.office_lamp" => true},
      groups: %{"light.office_group" => true}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    refute Repo.get_by(GroupLight, group_id: group.id, light_id: existing_light.id)
  end

  test "reimport preserve action keeps group memberships when upstream members do not resolve" do
    bridge = insert_bridge()

    existing_light =
      insert_light(bridge, %{
        source_id: "light.office_lamp",
        external_id: "ha:light.office_lamp"
      })

    group =
      insert_group(bridge, %{
        source_id: "light.office_group",
        external_id: "ha:light.office_group"
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: existing_light.id})

    normalized = %{
      rooms: [],
      lights: [],
      groups: [
        %{
          source: :ha,
          source_id: "light.office_group",
          name: "Office Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.missing_member"]}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "light.office_group", light_source_id: "light.missing_member"}
        ]
      }
    }

    plan = %{rooms: %{}, lights: %{}, groups: %{"light.office_group" => true}}

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.get_by(GroupLight, group_id: group.id, light_id: existing_light.id)
  end

  test "reimport with no selected entities does not create imported rooms" do
    bridge = insert_bridge()
    normalized = load_fixture("materialize_ha.json")

    plan = %{
      rooms: %{
        "office" => %{"action" => "create"},
        "studio" => %{"action" => "create"}
      },
      lights: %{
        "light.office_lamp" => false,
        "light.studio_a" => false,
        "light.studio_b" => false
      },
      groups: %{
        "light.office_group" => false,
        "light.studio_group" => false
      }
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    refute Repo.get_by(Room, name: "Office")
    refute Repo.get_by(Room, name: "Studio")
  end

  test "reimport preserve action does not duplicate a light when stable external id matches but source id changes" do
    bridge = insert_bridge(%{type: :caseta})

    light =
      insert_light(bridge, %{
        source: :caseta,
        source_id: "old-zone-id",
        external_id: "caseta-device-1"
      })

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :caseta,
          source_id: "new-zone-id",
          name: "Same Physical Light",
          capabilities: %{},
          identifiers: %{},
          metadata: %{"device_id" => "caseta-device-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    plan = %{rooms: %{}, lights: %{"new-zone-id" => true}, groups: %{}}

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.aggregate(Light, :count) == 1
    assert Repo.reload!(light).source_id == "new-zone-id"
  end

  test "reimport does not apply an identity refresh when the new source id is already occupied" do
    bridge = insert_bridge(%{type: :caseta})

    original =
      insert_light(bridge, %{
        source: :caseta,
        source_id: "old-zone-id",
        external_id: "caseta-device-1"
      })

    conflicting =
      insert_light(bridge, %{
        source: :caseta,
        source_id: "new-zone-id",
        external_id: "other-device",
        name: "Different Physical Light"
      })

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :caseta,
          source_id: "new-zone-id",
          name: "Same Physical Light",
          capabilities: %{},
          identifiers: %{},
          metadata: %{"device_id" => "caseta-device-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    plan = %{rooms: %{}, lights: %{"new-zone-id" => true}, groups: %{}}

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.aggregate(Light, :count) == 2
    assert Repo.reload!(original).source_id == "old-zone-id"
    assert Repo.reload!(conflicting).external_id == "other-device"
    assert Repo.reload!(conflicting).name == "Different Physical Light"
  end

  test "reimport preserve action does not duplicate a group when stable external id matches but source id changes" do
    bridge = insert_bridge(%{type: :caseta})

    group =
      insert_group(bridge, %{
        source: :caseta,
        source_id: "old-group-zone-id",
        external_id: "caseta-group-device-1"
      })

    normalized = %{
      rooms: [],
      lights: [],
      groups: [
        %{
          source: :caseta,
          source_id: "new-group-zone-id",
          name: "Same Physical Group",
          type: "group",
          capabilities: %{},
          metadata: %{"device_id" => "caseta-group-device-1"}
        }
      ],
      memberships: %{}
    }

    plan = %{rooms: %{}, lights: %{}, groups: %{"new-group-zone-id" => true}}

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.aggregate(Group, :count) == 1
    assert Repo.reload!(group).source_id == "new-group-zone-id"
  end

  test "initial HA import creates wrapper light duplicates as hidden canonical rows" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    ha_bridge = insert_bridge(%{type: :ha, import_complete: false, host: "10.0.0.50"})

    normalized = %{
      rooms: [%{source: :ha, source_id: "office", name: "Office", metadata: %{}}],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: "office",
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    :ok = Materialize.materialize(ha_bridge, normalized)

    ha_light = Repo.get_by!(Light, bridge_id: ha_bridge.id, source_id: "light.hue_lamp")
    assert ha_light.canonical_light_id == hue_light.id
    refute ha_light.enabled
    assert ha_light.room_id == nil
    assert ha_light.ha_export_mode == :none
    assert ha_light.homekit_export_mode == :none
    assert ha_light.display_name == "Hue Lamp via HA"
  end

  test "initial HA import creates wrapper group duplicates from canonicalized member lights" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group =
      insert_group(hue_bridge, %{
        source: :hue,
        source_id: "2"
      })

    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: false, host: "10.0.0.51"})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "light.hue_group", light_source_id: "light.hue_lamp"}
        ]
      }
    }

    :ok = Materialize.materialize(ha_bridge, normalized)

    ha_light = Repo.get_by!(Light, bridge_id: ha_bridge.id, source_id: "light.hue_lamp")
    ha_group = Repo.get_by!(Group, bridge_id: ha_bridge.id, source_id: "light.hue_group")

    assert ha_light.canonical_light_id == hue_light.id
    assert ha_group.canonical_group_id == hue_group.id
    refute ha_group.enabled
    assert ha_group.room_id == nil
    assert Repo.get_by(GroupLight, group_id: ha_group.id, light_id: ha_light.id)
  end

  test "reimport creates selected HA wrapper group duplicates as hidden canonical rows" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group = insert_group(hue_bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.57"})

    normalized = %{
      rooms: [%{source: :ha, source_id: "office", name: "Office", metadata: %{}}],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: "office",
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          room_source_id: "office",
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "light.hue_group", light_source_id: "light.hue_lamp"}
        ]
      }
    }

    plan = %{
      rooms: %{"office" => %{"action" => "create"}},
      lights: %{
        "light.hue_lamp" => %{"selected" => true, "resolution" => "import_hidden_duplicate"}
      },
      groups: %{
        "light.hue_group" => %{"selected" => true, "resolution" => "import_hidden_duplicate"}
      }
    }

    :ok = Materialize.materialize(ha_bridge, normalized, plan)

    ha_light = Repo.get_by!(Light, bridge_id: ha_bridge.id, source_id: "light.hue_lamp")
    ha_group = Repo.get_by!(Group, bridge_id: ha_bridge.id, source_id: "light.hue_group")

    assert ha_light.canonical_light_id == hue_light.id
    assert ha_group.canonical_group_id == hue_group.id
    refute ha_group.enabled
    assert ha_group.room_id == nil
    refute Repo.get_by(Room, name: "Office")
    assert Repo.get_by(GroupLight, group_id: ha_group.id, light_id: ha_light.id)
  end

  test "reimport creates selected HA wrapper group duplicates when members are visible linked entities" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group = insert_group(hue_bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.159"})

    ha_light =
      insert_light(ha_bridge, %{
        source: :ha,
        source_id: "light.hue_lamp",
        external_id: "ha-hue-lamp",
        canonical_light_id: hue_light.id,
        enabled: true,
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.hue_lamp",
          "metadata" => %{"unique_id" => "ha-hue-lamp"}
        }
      })

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "light.hue_group", light_source_id: "light.hue_lamp"}
        ]
      }
    }

    %{plan: plan} = ReimportPlan.build(normalized, NormalizeFromDb.normalize(ha_bridge), [])

    :ok = Materialize.materialize(ha_bridge, normalized, plan)

    ha_group = Repo.get_by!(Group, bridge_id: ha_bridge.id, source_id: "light.hue_group")

    assert ha_group.canonical_group_id == hue_group.id
    refute ha_group.enabled
    assert Repo.get_by(GroupLight, group_id: ha_group.id, light_id: ha_light.id)
  end

  test "reimport imports selected HA wrapper light duplicates as real entities when requested" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    insert_light(hue_bridge, %{
      source: :hue,
      source_id: "1",
      metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
    })

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.157"})
    room = insert_room("Office")

    normalized = %{
      rooms: [%{source: :ha, source_id: "office", name: "Office", metadata: %{}}],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: "office",
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    plan = %{
      rooms: %{"office" => %{"action" => "merge", "target_room_id" => "#{room.id}"}},
      lights: %{"light.hue_lamp" => %{"selected" => true, "resolution" => "import_real"}},
      groups: %{}
    }

    :ok = Materialize.materialize(ha_bridge, normalized, plan)

    ha_light = Repo.get_by!(Light, bridge_id: ha_bridge.id, source_id: "light.hue_lamp")
    assert ha_light.canonical_light_id == nil
    assert ha_light.enabled
    assert ha_light.room_id == room.id
  end

  test "reimport imports selected HA wrapper group duplicates as real entities when requested" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group = insert_group(hue_bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.158"})
    room = insert_room("Office")

    normalized = %{
      rooms: [%{source: :ha, source_id: "office", name: "Office", metadata: %{}}],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: "office",
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          room_source_id: "office",
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "light.hue_group", light_source_id: "light.hue_lamp"}
        ]
      }
    }

    plan = %{
      rooms: %{"office" => %{"action" => "merge", "target_room_id" => "#{room.id}"}},
      lights: %{"light.hue_lamp" => %{"selected" => true, "resolution" => "import_real"}},
      groups: %{"light.hue_group" => %{"selected" => true, "resolution" => "import_real"}}
    }

    :ok = Materialize.materialize(ha_bridge, normalized, plan)

    ha_light = Repo.get_by!(Light, bridge_id: ha_bridge.id, source_id: "light.hue_lamp")
    ha_group = Repo.get_by!(Group, bridge_id: ha_bridge.id, source_id: "light.hue_group")

    assert ha_light.canonical_light_id == nil
    assert ha_group.canonical_group_id == nil
    assert ha_group.enabled
    assert ha_group.room_id == room.id
    assert Repo.get_by(GroupLight, group_id: ha_group.id, light_id: ha_light.id)
  end

  test "reimport aborts when a selected HA group duplicate is invalidated by member choices" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group = insert_group(hue_bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.58"})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "light.hue_group", light_source_id: "light.hue_lamp"}
        ]
      }
    }

    plan = %{
      rooms: %{},
      lights: %{"light.hue_lamp" => false},
      groups: %{
        "light.hue_group" => %{"selected" => true, "resolution" => "import_hidden_duplicate"}
      }
    }

    assert {:error, {:invalid_duplicate, :group, "light.hue_group"}} =
             Materialize.materialize(ha_bridge, normalized, plan)

    refute Repo.get_by(Light, bridge_id: ha_bridge.id, source_id: "light.hue_lamp")
    refute Repo.get_by(Group, bridge_id: ha_bridge.id, source_id: "light.hue_group")
  end

  test "reimport imports native groups as real even when their member set matches an existing native group" do
    bridge = insert_bridge(%{type: :hue, import_complete: true})

    light = insert_light(bridge, %{source: :hue, source_id: "1"})
    existing_group = insert_group(bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: existing_group.id, light_id: light.id})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :hue,
          source_id: "1",
          name: "Hue Lamp",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :hue,
          source_id: "3",
          name: "Another Hue Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["1"]}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "3", light_source_id: "1"}
        ]
      }
    }

    plan = %{rooms: %{}, lights: %{"1" => true}, groups: %{"3" => true}}

    :ok = Materialize.materialize(bridge, normalized, plan)

    new_group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "3")
    assert new_group.canonical_group_id == nil
    assert new_group.enabled
    assert Repo.get_by(GroupLight, group_id: new_group.id, light_id: light.id)
  end

  test "duplicate matching imports HA wrappers as real when the physical identifier match is not unique" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})

    insert_light(hue_bridge, %{
      source: :hue,
      source_id: "1",
      metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
    })

    insert_light(hue_bridge, %{
      source: :hue,
      source_id: "2",
      metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
    })

    ha_bridge = insert_bridge(%{type: :ha, import_complete: false, host: "10.0.0.52"})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.ambiguous",
          name: "Ambiguous HA Light",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-ambiguous"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    :ok = Materialize.materialize(ha_bridge, normalized)

    ha_light = Repo.get_by!(Light, bridge_id: ha_bridge.id, source_id: "light.ambiguous")
    assert ha_light.canonical_light_id == nil
    assert ha_light.enabled
  end

  test "empty HA groups do not become hidden duplicates of empty native groups" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})
    insert_group(hue_bridge, %{source: :hue, source_id: "empty-native"})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: false, host: "10.0.0.53"})

    normalized = %{
      rooms: [],
      lights: [],
      groups: [
        %{
          source: :ha,
          source_id: "light.empty_group",
          name: "Empty HA Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"members" => []}
        }
      ],
      memberships: %{}
    }

    :ok = Materialize.materialize(ha_bridge, normalized)

    ha_group = Repo.get_by!(Group, bridge_id: ha_bridge.id, source_id: "light.empty_group")
    assert ha_group.canonical_group_id == nil
    assert ha_group.enabled
  end

  test "reimport auto-deletes missing hidden duplicate rows" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})
    hue_light = insert_light(hue_bridge, %{source: :hue, source_id: "1", external_id: "hue-1"})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.54"})

    hidden =
      insert_light(ha_bridge, %{
        source: :ha,
        source_id: "light.missing_wrapper",
        canonical_light_id: hue_light.id,
        enabled: false,
        room_id: nil
      })

    normalized = %{rooms: [], lights: [], groups: [], memberships: %{}}
    plan = %{rooms: %{}, lights: %{}, groups: %{}}

    :ok = Materialize.materialize(ha_bridge, normalized, plan)

    refute Repo.get(Light, hidden.id)
  end

  test "reimport keeps an existing hidden duplicate row when it is present upstream but unchecked" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})
    hue_light = insert_light(hue_bridge, %{source: :hue, source_id: "1"})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.154"})

    hidden =
      insert_light(ha_bridge, %{
        source: :ha,
        source_id: "light.hue_lamp",
        external_id: "ha-hue-lamp",
        canonical_light_id: hue_light.id,
        enabled: false,
        room_id: nil
      })

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    plan = %{rooms: %{}, lights: %{"light.hue_lamp" => false}, groups: %{}}

    :ok = Materialize.materialize(ha_bridge, normalized, plan)

    assert Repo.get(Light, hidden.id)
  end

  test "initial HA import filters HueWorks exported entities by unique id" do
    ha_bridge = insert_bridge(%{type: :ha, import_complete: false, host: "10.0.0.55"})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hueworks_light_12_switch",
          name: "HueWorks Exported Lamp",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{"unique_id" => "hueworks_light_12_switch"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hueworks_group_7",
          name: "HueWorks Exported Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"unique_id" => "hueworks_group_7_light"}
        }
      ],
      memberships: %{}
    }

    :ok = Materialize.materialize(ha_bridge, normalized)

    refute Repo.get_by(Light,
             bridge_id: ha_bridge.id,
             source_id: "light.hueworks_light_12_switch"
           )

    refute Repo.get_by(Group, bridge_id: ha_bridge.id, source_id: "light.hueworks_group_7")
  end

  test "explicit reimport delete removes hidden duplicates that target a deleted canonical light" do
    hue_bridge = insert_bridge(%{type: :hue, import_complete: true})
    hue_light = insert_light(hue_bridge, %{source: :hue, source_id: "1", external_id: "hue-1"})

    ha_bridge = insert_bridge(%{type: :ha, import_complete: true, host: "10.0.0.56"})

    hidden =
      insert_light(ha_bridge, %{
        source: :ha,
        source_id: "light.hue_lamp",
        canonical_light_id: hue_light.id,
        enabled: false,
        room_id: nil
      })

    normalized = %{rooms: [], lights: [], groups: [], memberships: %{}}

    plan = %{
      rooms: %{},
      lights: %{"1" => %{"resolution" => "delete", "expected_external_id" => "hue-1"}},
      groups: %{}
    }

    :ok = Materialize.materialize(hue_bridge, normalized, plan)

    refute Repo.get(Light, hue_light.id)
    refute Repo.get(Light, hidden.id)
  end

  test "destructive reimport resolutions abort when the reviewed entity is stale" do
    bridge = insert_bridge()

    light =
      insert_light(bridge, %{
        source_id: "light.missing",
        external_id: "old-external-id"
      })

    normalized = %{rooms: [], lights: [], groups: [], memberships: %{}}

    plan = %{
      rooms: %{},
      lights: %{
        "light.missing" => %{
          "selected" => false,
          "resolution" => "disable",
          "expected_external_id" => "reviewed-external-id"
        }
      },
      groups: %{}
    }

    assert {:error, {:stale_resolution, :light, "light.missing"}} =
             Materialize.materialize(bridge, normalized, plan)

    assert Repo.reload!(light).enabled
  end

  test "reimport preserve action does not clear rooms when the bridge reports no room" do
    bridge = insert_bridge()
    room = insert_room("User Assigned Room")

    light = insert_light(bridge, %{source_id: "light.office_lamp", room_id: room.id})
    group = insert_group(bridge, %{source_id: "light.office_group", room_id: room.id})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.office_group",
          name: "Office Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{}
    }

    plan = %{
      rooms: %{},
      lights: %{"light.office_lamp" => true},
      groups: %{"light.office_group" => true}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.reload!(light).room_id == room.id
    assert Repo.reload!(group).room_id == room.id
  end

  test "reimport preserve action does not re-infer an existing group's room from member lights" do
    bridge = insert_bridge()
    group_room = insert_room("Group Room")
    light_room = insert_room("Light Room")

    light = insert_light(bridge, %{source_id: "light.office_lamp", room_id: light_room.id})
    group = insert_group(bridge, %{source_id: "light.office_group", room_id: group_room.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})

    normalized = %{
      rooms: [%{source: :ha, source_id: "office", name: "Light Room", metadata: %{}}],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          room_source_id: "office",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.office_group",
          name: "Office Group",
          room_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "light.office_group", light_source_id: "light.office_lamp"}
        ]
      }
    }

    plan = %{
      rooms: %{"office" => %{"action" => "merge", "target_room_id" => "#{light_room.id}"}},
      lights: %{"light.office_lamp" => true},
      groups: %{"light.office_group" => true}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.reload!(light).room_id == light_room.id
    assert Repo.reload!(group).room_id == group_room.id
  end

  test "reimport does not recreate a room the user renamed when no new entities are imported" do
    bridge = insert_bridge()
    renamed_room = insert_room("Workshop")

    light = insert_light(bridge, %{source_id: "light.office_lamp", room_id: renamed_room.id})

    normalized = %{
      rooms: [%{source: :ha, source_id: "office", name: "Office", metadata: %{}}],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          room_source_id: "office",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    # Default reimport plan when the bridge room name no longer matches any
    # HueWorks room (the user renamed it): the room falls back to "create"
    # even though every entity in it already exists.
    plan = %{
      rooms: %{"office" => %{"action" => "create", "target_room_id" => nil}},
      lights: %{"light.office_lamp" => true},
      groups: %{}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    refute Repo.get_by(Room, name: "Office")
    assert Repo.reload!(light).room_id == renamed_room.id
  end

  test "materialize without an explicit review plan refuses to reimport completed bridges" do
    bridge = insert_bridge(%{import_complete: true})

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.new",
          name: "New Light",
          room_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    assert {:error, :reimport_requires_review} = Materialize.materialize(bridge, normalized)
    refute Repo.get_by(Light, bridge_id: bridge.id, source_id: "light.new")
  end

  defp load_fixture(name) do
    path = Path.join(["test", "fixtures", "normalize", name])
    path |> File.read!() |> Jason.decode!()
  end

  defp insert_bridge(attrs \\ %{}) do
    defaults = %{
      type: :ha,
      name: "Home Assistant",
      host: "10.0.0.2",
      credentials: %{"token" => "token"},
      import_complete: true,
      enabled: true
    }

    %Bridge{}
    |> Bridge.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_room(name) do
    Repo.insert!(%Room{name: name})
  end

  defp insert_light(bridge, attrs) do
    defaults = %{
      name: "Existing Light",
      source: :ha,
      source_id: "light.existing",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{},
      normalized_json: %{}
    }

    %Light{}
    |> Light.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_group(bridge, attrs) do
    defaults = %{
      name: "Existing Group",
      source: :ha,
      source_id: "light.existing_group",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{},
      normalized_json: %{}
    }

    %Group{}
    |> Group.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
