defmodule Hueworks.Import.ReimportReviewTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.ReimportReview
  alias Hueworks.Schemas.{Bridge, Group, Light, Room}

  test "groups removed and existing entities by HueWorks room and new entities by bridge room" do
    bridge = %Bridge{id: 10, type: :hue}
    main_floor = %Room{id: 1, name: "Main Floor"}

    existing = %Light{
      id: 1,
      name: "Bridge Lamp",
      display_name: "Office Lamp",
      source: :hue,
      source_id: "light-1",
      external_id: "uid-1",
      bridge_id: 10,
      room: main_floor,
      enabled: true,
      metadata: %{"uniqueid" => "uid-1", "identifiers" => %{}},
      normalized_json: %{}
    }

    removed = %Light{
      id: 2,
      name: "Old Lamp",
      display_name: "Old Lamp",
      source: :hue,
      source_id: "light-old",
      external_id: "uid-old",
      bridge_id: 10,
      room: main_floor,
      enabled: true,
      metadata: %{},
      normalized_json: %{}
    }

    normalized = %{
      rooms: [%{source_id: "bridge-office", name: "Office"}],
      lights: [
        %{
          source: :hue,
          source_id: "light-1",
          name: "Renamed Bridge Lamp",
          room_source_id: "bridge-office",
          capabilities: %{},
          identifiers: %{},
          metadata: %{"uniqueid" => "uid-1"}
        },
        %{
          source: :hue,
          source_id: "light-new",
          name: "New Lamp",
          room_source_id: "bridge-office",
          capabilities: %{},
          identifiers: %{},
          metadata: %{"uniqueid" => "uid-new"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    reimport = %{
      statuses: %{
        lights: %{"light-1" => :existing, "light-new" => :new, "light-old" => :missing},
        groups: %{}
      }
    }

    plan = %{
      lights: %{
        "light-1" => true,
        "light-new" => false,
        "light-old" => %{"selected" => false, "resolution" => "keep"}
      },
      groups: %{},
      rooms: %{}
    }

    review =
      ReimportReview.build(bridge, normalized, reimport, plan, [existing, removed], [], [
        main_floor
      ])

    assert [%{room: "Main Floor", items: [%{name: "Old Lamp"}]}] = review.removed
    assert [%{room: "Main Floor", automatic_updates: [existing_item]}] = review.existing
    assert existing_item.name == "Office Lamp"
    assert Enum.any?(existing_item.changes, &(&1.field == :name))
    assert [%{room: "Office", items: [%{name: "New Lamp", selected?: false}]}] = review.new

    assert review.summary == %{
             removed: 1,
             existing: 1,
             new: 1,
             automatic_updates: 1,
             unchanged: 0,
             membership_warnings: 0,
             hidden_duplicates: 0
           }
  end

  test "reports unresolved group members and clears the warning when the new light is selected" do
    bridge = %Bridge{id: 10, type: :ha}
    room = %Room{id: 1, name: "Kitchen"}

    group = %Group{
      id: 3,
      name: "Kitchen",
      display_name: "Kitchen",
      source: :ha,
      source_id: "group.kitchen",
      external_id: "group-uid",
      bridge_id: 10,
      room: room,
      lights: [],
      enabled: true,
      metadata: %{"unique_id" => "group-uid"},
      normalized_json: %{}
    }

    normalized = %{
      rooms: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.new",
          name: "New Light",
          capabilities: %{},
          identifiers: %{},
          metadata: %{"unique_id" => "light-uid"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "group.kitchen",
          name: "Kitchen",
          capabilities: %{},
          metadata: %{"unique_id" => "group-uid"}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "group.kitchen", light_source_id: "light.new"}
        ]
      }
    }

    reimport = %{
      statuses: %{
        lights: %{"light.new" => :new},
        groups: %{"group.kitchen" => :existing}
      }
    }

    default_plan = %{
      lights: %{"light.new" => false},
      groups: %{"group.kitchen" => true},
      rooms: %{}
    }

    default_review =
      ReimportReview.build(bridge, normalized, reimport, default_plan, [], [group], [room])

    assert default_review.summary.membership_warnings == 1

    warning =
      default_review.existing
      |> hd()
      |> Map.fetch!(:membership_warnings)
      |> hd()
      |> Map.fetch!(:membership_warning)

    assert warning.unresolved_source_ids == ["light.new"]

    selected_plan = put_in(default_plan, [:lights, "light.new"], true)

    selected_review =
      ReimportReview.build(bridge, normalized, reimport, selected_plan, [], [group], [room])

    assert selected_review.summary.membership_warnings == 0

    [group_item] = selected_review.existing |> hd() |> Map.fetch!(:automatic_updates)
    assert Enum.any?(group_item.changes, &(&1.field == :membership))
  end
end
