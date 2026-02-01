defmodule Hueworks.Import.ReimportPlanTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.ReimportPlan

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
    assert plan.lights["light-2"] == false

    assert statuses.lights["light-1"] == :existing
    assert statuses.lights["light-2"] == :new

    assert plan.rooms["room-1"]["action"] == "merge"
    assert plan.rooms["room-1"]["target_room_id"] == "1"
  end

  test "deletions include missing and unchecked existing entries" do
    normalized_import = %{
      rooms: [],
      lights: [
        %{
          source: :hue,
          source_id: "light-1",
          name: "Lamp",
          identifiers: %{},
          metadata: %{"uniqueid" => "hue-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    normalized_db = %{
      rooms: [],
      lights: [
        %{"source" => "hue", "source_id" => "light-1", "metadata" => %{"uniqueid" => "hue-1"}},
        %{"source" => "hue", "source_id" => "light-2", "metadata" => %{"uniqueid" => "hue-2"}}
      ],
      groups: [],
      memberships: %{}
    }

    plan = %{lights: %{"light-1" => false}, groups: %{}, rooms: %{}}

    deletions = ReimportPlan.deletions(plan, normalized_import, normalized_db)

    assert Enum.sort(deletions.lights) == ["hue-1", "hue-2"]
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
end
