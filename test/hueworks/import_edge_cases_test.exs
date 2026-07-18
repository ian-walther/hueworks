defmodule Hueworks.Import.EdgeCasesTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.{Materialize, Normalize, Plan}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, Area}

  defp insert_bridge(attrs) do
    defaults = %{
      type: :ha,
      name: "Bridge",
      host: "10.0.0.50",
      credentials: %{"token" => "token"},
      import_complete: false,
      enabled: true
    }

    insert_bridge!(Map.merge(defaults, attrs))
  end

  test "normalize handles empty raw payloads" do
    bridge_hue = %Bridge{id: 1, type: :hue, name: "Hue", host: "10.0.0.1"}
    bridge_ha = %Bridge{id: 2, type: :ha, name: "HA", host: "10.0.0.2"}
    bridge_caseta = %Bridge{id: 3, type: :caseta, name: "Caseta", host: "10.0.0.3"}
    bridge_z2m = %Bridge{id: 4, type: :z2m, name: "Z2M", host: "10.0.0.4"}

    for bridge <- [bridge_hue, bridge_ha, bridge_caseta, bridge_z2m] do
      normalized = Normalize.normalize(bridge, %{})
      assert normalized.schema_version == 1
      assert normalized.areas == []
      assert normalized.lights == []
      assert normalized.groups == []
      assert normalized.memberships.area_groups == []
      assert normalized.memberships.area_lights == []
      assert normalized.memberships.group_lights == []
    end
  end

  test "plan build skips nil source ids and normalizes numeric ids" do
    normalized = %{
      areas: [
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

    assert Map.has_key?(plan.areas, "1")
    assert Map.has_key?(plan.areas, "1.5")
    refute Map.has_key?(plan.areas, nil)

    assert plan.lights["10"] == true
    assert plan.lights["11"] == true

    assert plan.groups["20.2"] == true
    assert plan.groups["21"] == true
  end

  test "materialize respects plan selection and skips memberships" do
    bridge = insert_bridge(%{type: :ha, host: "10.0.0.51"})

    normalized = %{
      areas: [
        %{source_id: "area-1", name: "Office"}
      ],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          area_source_id: "area-1",
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
          area_source_id: "area-1",
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
      "areas" => %{
        "area-1" => %{"action" => "skip"}
      },
      "lights" => %{
        "light.office_lamp" => false
      },
      "groups" => %{
        "light.office_group" => true
      }
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    assert Repo.aggregate(Area, :count) == 0
    assert Repo.aggregate(Light, :count) == 0

    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "light.office_group")
    assert group.area_id == nil

    refute Repo.get_by(GroupLight, group_id: group.id)
  end

  test "materialize merges areas into target area when requested" do
    bridge = insert_bridge(%{type: :ha, host: "10.0.0.52"})

    target_area = Repo.insert!(%Area{name: "Existing"})

    normalized = %{
      areas: [
        %{source_id: "area-1", name: "Office"}
      ],
      lights: [
        %{
          source: :ha,
          source_id: "light.office_lamp",
          name: "Office Lamp",
          area_source_id: "area-1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    plan = %{
      "areas" => %{
        "area-1" => %{"action" => "merge", "target_area_id" => Integer.to_string(target_area.id)}
      },
      "lights" => %{},
      "groups" => %{}
    }

    :ok = Materialize.materialize(bridge, normalized, plan)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.office_lamp")
    assert light.area_id == target_area.id
    assert Repo.aggregate(Area, :count) == 1
  end
end
