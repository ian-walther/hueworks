defmodule Hueworks.Import.PlanApplicationTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.Materialize
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light, Area}

  defp insert_bridge(attrs \\ %{}) do
    defaults = %{
      type: :hue,
      name: "Hue Bridge",
      host: "10.0.0.200",
      credentials: %{"api_key" => "key"},
      import_complete: false,
      enabled: true
    }

    insert_bridge!(Map.merge(defaults, attrs))
  end

  test "area skip plan does not create a new area" do
    bridge = insert_bridge()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    plan = %{
      "areas" => %{
        "1" => %{"action" => "skip"}
      },
      "lights" => %{},
      "groups" => %{}
    }

    assert :ok == Materialize.materialize(bridge, normalized, plan)
    assert Repo.aggregate(Area, :count) == 0
  end

  test "area merge plan assigns lights to target area" do
    bridge = insert_bridge(%{host: "10.0.0.201"})
    target_area = Repo.insert!(%Area{name: "Existing"})

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        }
      ],
      lights: [
        %{
          source: :hue,
          source_id: "1",
          name: "Lamp",
          area_source_id: "1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :hue,
          source_id: "2",
          name: "Office Group",
          area_source_id: "1",
          type: "group",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{}
    }

    plan = %{
      "areas" => %{
        "1" => %{"action" => "merge", "target_area_id" => Integer.to_string(target_area.id)}
      },
      "lights" => %{"1" => true},
      "groups" => %{"2" => true}
    }

    assert :ok == Materialize.materialize(bridge, normalized, plan)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "1")
    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "2")

    assert light.area_id == target_area.id
    assert group.area_id == target_area.id
    assert Repo.aggregate(Area, :count) == 1
  end

  test "area skip does not delete existing area" do
    bridge = insert_bridge(%{host: "10.0.0.202"})
    existing_area = Repo.insert!(%Area{name: "Office"})

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    plan = %{
      "areas" => %{
        "1" => %{"action" => "skip"}
      },
      "lights" => %{},
      "groups" => %{}
    }

    assert :ok == Materialize.materialize(bridge, normalized, plan)
    assert Repo.get(Area, existing_area.id)
    assert Repo.aggregate(Area, :count) == 1
  end

  test "per-entity target area assigns unassigned lights and groups to an existing area" do
    bridge = insert_bridge(%{host: "10.0.0.203"})
    target_area = Repo.insert!(%Area{name: "Assigned"})

    normalized = %{
      areas: [],
      lights: [
        %{
          source: :hue,
          source_id: "1",
          name: "Lamp",
          area_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :hue,
          source_id: "2",
          name: "Group",
          area_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{}
    }

    plan = %{
      "areas" => %{},
      "lights" => %{
        "1" => %{"selected" => true, "target_area_id" => Integer.to_string(target_area.id)}
      },
      "groups" => %{
        "2" => %{"selected" => true, "target_area_id" => Integer.to_string(target_area.id)}
      }
    }

    assert :ok == Materialize.materialize(bridge, normalized, plan)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "1")
    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "2")

    assert light.area_id == target_area.id
    assert group.area_id == target_area.id
  end
end
