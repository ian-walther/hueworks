defmodule Hueworks.Import.EdgeCasesTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.{Materialize, Normalize, Plan}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, Room}

  defp insert_bridge(attrs) do
    defaults = %{
      type: :ha,
      name: "Bridge",
      host: "10.0.0.50",
      credentials: %{"token" => "token"},
      import_complete: false,
      enabled: true
    }

    Repo.insert!(struct(Bridge, Map.merge(defaults, attrs)))
  end

  test "normalize handles empty raw payloads" do
    bridge_hue = %Bridge{id: 1, type: :hue, name: "Hue", host: "10.0.0.1"}
    bridge_ha = %Bridge{id: 2, type: :ha, name: "HA", host: "10.0.0.2"}
    bridge_caseta = %Bridge{id: 3, type: :caseta, name: "Caseta", host: "10.0.0.3"}

    for bridge <- [bridge_hue, bridge_ha, bridge_caseta] do
      normalized = Normalize.normalize(bridge, %{})
      assert normalized.schema_version == 1
      assert normalized.rooms == []
      assert normalized.lights == []
      assert normalized.groups == []
      assert normalized.memberships.room_groups == []
      assert normalized.memberships.room_lights == []
      assert normalized.memberships.group_lights == []
    end
  end

  test "plan build skips nil source ids and normalizes numeric ids" do
    normalized = %{
      rooms: [
        %{source_id: 1, name: "Office"},
        %{source_id: 1.5, name: "Kitchen"},
        %{source_id: nil, name: "Missing"}
      ],
      lights: [
        %{source_id: 10},
        %{source_id: "11"},
        %{source_id: nil}
      ],
      groups: [
        %{source_id: 20.2},
        %{source_id: "21"}
      ]
    }

    plan = Plan.build_default(normalized)

    assert Map.has_key?(plan.rooms, "1")
    assert Map.has_key?(plan.rooms, "1.5")
    refute Map.has_key?(plan.rooms, nil)

    assert plan.lights["10"] == true
    assert plan.lights["11"] == true

    assert plan.groups["20.2"] == true
    assert plan.groups["21"] == true
  end

  test "materialize respects plan selection and skips memberships" do
    bridge = insert_bridge(%{type: :ha, host: "10.0.0.51"})

    normalized = %{
      rooms: [
        %{source_id: "room-1", name: "Office"}
      ],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          room_source_id: "room-1",
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
          room_source_id: "room-1",
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
      "rooms" => %{
        "room-1" => %{"action" => "skip"}
      },
      "lights" => %{
        "light.office_lamp" => false
      },
      "groups" => %{
        "light.office_group" => true
      }
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.aggregate(Room, :count) == 0
    assert Repo.aggregate(Light, :count) == 0

    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "light.office_group")
    assert group.room_id == nil

    refute Repo.get_by(GroupLight, group_id: group.id)
  end

  test "materialize merges rooms into target room when requested" do
    bridge = insert_bridge(%{type: :ha, host: "10.0.0.52"})

    target_room = Repo.insert!(%Room{name: "Existing"})

    normalized = %{
      rooms: [
        %{source_id: "room-1", name: "Office"}
      ],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          room_source_id: "room-1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    plan = %{
      "rooms" => %{
        "room-1" => %{"action" => "merge", "target_room_id" => Integer.to_string(target_room.id)}
      },
      "lights" => %{},
      "groups" => %{}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.office_lamp")
    assert light.room_id == target_room.id
    assert Repo.aggregate(Room, :count) == 1
  end
end
