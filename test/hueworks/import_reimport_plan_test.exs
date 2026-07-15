defmodule Hueworks.Import.ReimportPlanTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.{NormalizeFromDb, ReimportPlan}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light}

  test "build marks existing entries as selected and new as unchecked" do
    normalized_import = %{
      rooms: [
        %{source: :hue, source_id: "room-1", name: "Office", normalized_name: "office"}
      ],
      lights: [
        %{
          source: :hue,
          source_id: "light-1",
          name: "Lamp",
          identifiers: %{},
          metadata: %{"uniqueid" => "hue-1"}
        },
        %{
          source: :hue,
          source_id: "light-2",
          name: "New Lamp",
          identifiers: %{},
          metadata: %{"uniqueid" => "hue-2"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    normalized_db = %{
      rooms: [],
      lights: [
        %{"source" => "hue", "source_id" => "light-1", "metadata" => %{"uniqueid" => "hue-1"}}
      ],
      groups: [],
      memberships: %{}
    }

    rooms = [%{id: 1, name: "Office"}]

    %{plan: plan, statuses: statuses} =
      ReimportPlan.build(normalized_import, normalized_db, rooms)

    assert plan.lights["light-1"] == true

    assert plan.lights["light-2"] == %{
             "selected" => false,
             "resolution" => "do_not_import",
             "target_room_id" => "unassigned"
           }

    assert statuses.lights["light-1"] == :existing
    assert statuses.lights["light-2"] == :new

    assert plan.rooms["room-1"]["action"] == "merge"
    assert plan.rooms["room-1"]["target_room_id"] == "1"
  end

  test "build selects HA wrapper light duplicates by default and filters HueWorks exports" do
    hue_bridge = insert_bridge(:hue)

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        },
        %{
          source: :ha,
          source_id: "light.hueworks_light_#{hue_light.id}_switch",
          name: "HueWorks Export",
          identifiers: %{},
          metadata: %{"unique_id" => "hueworks_light_#{hue_light.id}_switch"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    %{plan: plan, statuses: statuses, normalized: normalized} =
      ReimportPlan.build(normalized_import, %{lights: [], groups: []}, [])

    assert plan.lights["light.hue_lamp"] == %{
             "selected" => true,
             "resolution" => "import_hidden_duplicate"
           }

    assert statuses.lights["light.hue_lamp"] == :duplicate
    refute Map.has_key?(plan.lights, "light.hueworks_light_#{hue_light.id}_switch")

    refute Enum.any?(
             normalized["lights"],
             &(&1["source_id"] == "light.hueworks_light_#{hue_light.id}_switch")
           )
  end

  test "build selects HA wrapper group duplicates by default after member canonicalization" do
    hue_bridge = insert_bridge(:hue)

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group = insert_group(hue_bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{}
    }

    %{plan: plan, statuses: statuses} =
      ReimportPlan.build(normalized_import, %{lights: [], groups: []}, [])

    assert plan.groups["light.hue_group"] == %{
             "selected" => true,
             "resolution" => "import_hidden_duplicate"
           }

    assert statuses.groups["light.hue_group"] == :duplicate
  end

  test "build selects HA wrapper group duplicates when member lights already exist as hidden duplicates" do
    hue_bridge = insert_bridge(:hue)

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group = insert_group(hue_bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge = insert_bridge(:ha)

    insert_light(ha_bridge, %{
      source: :ha,
      source_id: "light.hue_lamp",
      external_id: "ha-hue-lamp",
      canonical_light_id: hue_light.id,
      enabled: false,
      room_id: nil,
      normalized_json: %{
        "source" => "ha",
        "source_id" => "light.hue_lamp",
        "metadata" => %{"unique_id" => "ha-hue-lamp"}
      }
    })

    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          identifiers: %{},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{}
    }

    %{plan: plan, statuses: statuses} =
      ReimportPlan.build(normalized_import, NormalizeFromDb.normalize(ha_bridge), [])

    assert plan.groups["light.hue_group"] == %{
             "selected" => true,
             "resolution" => "import_hidden_duplicate"
           }

    assert statuses.groups["light.hue_group"] == :duplicate
  end

  test "build selects HA wrapper group duplicates when member lights already exist as visible linked entities" do
    hue_bridge = insert_bridge(:hue)

    hue_light =
      insert_light(hue_bridge, %{
        source: :hue,
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    hue_group = insert_group(hue_bridge, %{source: :hue, source_id: "2"})
    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge = insert_bridge(:ha)

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

    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "Hue Lamp via HA",
          identifiers: %{},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "light.hue_group",
          name: "Hue Group via HA",
          type: "group",
          capabilities: %{},
          metadata: %{"members" => ["light.hue_lamp"]}
        }
      ],
      memberships: %{}
    }

    %{plan: plan, statuses: statuses} =
      ReimportPlan.build(normalized_import, NormalizeFromDb.normalize(ha_bridge), [])

    assert plan.groups["light.hue_group"] == %{
             "selected" => true,
             "resolution" => "import_hidden_duplicate"
           }

    assert statuses.groups["light.hue_group"] == :duplicate
  end

  test "build surfaces source id and stable identifier conflicts as ambiguous identity" do
    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :caseta,
          source_id: "zone-2",
          name: "Same Physical Light",
          identifiers: %{},
          metadata: %{"device_id" => "caseta-device-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    normalized_db = %{
      rooms: [],
      lights: [
        %{
          "source" => "caseta",
          "source_id" => "zone-1",
          "metadata" => %{"device_id" => "caseta-device-1"}
        },
        %{
          "source" => "caseta",
          "source_id" => "zone-2",
          "metadata" => %{"device_id" => "caseta-device-2"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    %{plan: plan, statuses: statuses} =
      ReimportPlan.build(normalized_import, normalized_db, [])

    assert statuses.lights["zone-2"] == :ambiguous_identity
    assert plan.lights["zone-2"] == %{"selected" => false, "resolution" => "keep_separate"}
  end

  test "build uses HA entity_id as stable identifier" do
    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.kitchen",
          name: "Kitchen",
          metadata: %{"entity_id" => "light.kitchen"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    normalized_db = %{
      rooms: [],
      lights: [
        %{
          "source" => "ha",
          "source_id" => "light.kitchen",
          "metadata" => %{"entity_id" => "light.kitchen"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    %{plan: plan, statuses: statuses} =
      ReimportPlan.build(normalized_import, normalized_db, [])

    assert plan.lights["light.kitchen"] == true
    assert statuses.lights["light.kitchen"] == :existing
  end

  test "build uses Caseta device_id as stable identifier" do
    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :caseta,
          source_id: "zone-1",
          name: "Entry",
          metadata: %{"device_id" => "caseta-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    normalized_db = %{
      rooms: [],
      lights: [
        %{
          "source" => "caseta",
          "source_id" => "zone-1",
          "metadata" => %{"device_id" => "caseta-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    %{plan: plan, statuses: statuses} =
      ReimportPlan.build(normalized_import, normalized_db, [])

    assert plan.lights["zone-1"] == true
    assert statuses.lights["zone-1"] == :existing
  end

  test "new entities in unmatched bridge rooms default to do not import and unassigned" do
    normalized_import = %{
      rooms: [%{source_id: "bridge-office", name: "Bridge Office"}],
      lights: [
        %{
          source: :hue,
          source_id: "light-new",
          name: "New Lamp",
          room_source_id: "bridge-office",
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    %{plan: plan} = ReimportPlan.build(normalized_import, %{lights: [], groups: []}, [])

    assert plan.rooms["bridge-office"]["action"] == "skip"

    assert plan.lights["light-new"] == %{
             "selected" => false,
             "resolution" => "do_not_import",
             "target_room_id" => "unassigned"
           }
  end

  test "new entities preselect an existing HueWorks room only for a normalized name match" do
    normalized_import = %{
      rooms: [%{source_id: "bridge-office", name: "Office", normalized_name: "office"}],
      lights: [
        %{
          source: :hue,
          source_id: "light-new",
          name: "New Lamp",
          room_source_id: "bridge-office",
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    %{plan: plan} =
      ReimportPlan.build(normalized_import, %{lights: [], groups: []}, [
        %{id: 42, name: "OFFICE"}
      ])

    assert plan.rooms["bridge-office"]["action"] == "merge"
    assert plan.lights["light-new"]["target_room_id"] == "42"
  end

  defp insert_bridge(type) do
    %Bridge{}
    |> Bridge.changeset(%{
      type: type,
      name: "#{type} Bridge",
      host: "10.0.0.#{System.unique_integer([:positive])}",
      credentials: %{},
      enabled: true,
      import_complete: true
    })
    |> Repo.insert!()
  end

  defp insert_light(bridge, attrs) do
    defaults = %{
      name: "Light",
      display_name: "Light",
      source: bridge.type,
      source_id: "light-#{System.unique_integer([:positive])}",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{}
    }

    %Light{}
    |> Light.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_group(bridge, attrs) do
    defaults = %{
      name: "Group",
      display_name: "Group",
      source: bridge.type,
      source_id: "group-#{System.unique_integer([:positive])}",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{}
    }

    %Group{}
    |> Group.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
