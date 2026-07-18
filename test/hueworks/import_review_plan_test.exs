defmodule Hueworks.Import.ReviewPlanTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.ReviewPlan
  alias Hueworks.Schemas.Area

  test "entity resolution writer matches destructive apply reader semantics" do
    plan = %{
      lights: %{
        "light-1" => %{"selected" => true, "expected_external_id" => "light-uid"}
      }
    }

    updated = ReviewPlan.put_entity_resolution(plan, "lights", "light-1", "delete")

    refute ReviewPlan.selected?(updated, :lights, "light-1")
    assert ReviewPlan.entity_resolution(updated, :lights, "light-1") == "delete"

    assert [
             %{
               type: :light,
               source_id: "light-1",
               action: :delete,
               expected_external_id: "light-uid"
             }
           ] = ReviewPlan.destructive_resolutions(updated)
  end

  test "destructive resolution reader accepts action or resolution keys" do
    plan = %{
      lights: %{"light-1" => %{"action" => "disable"}},
      groups: %{"group-1" => %{"resolution" => "delete"}}
    }

    assert [
             %{type: :light, source_id: "light-1", action: :disable},
             %{type: :group, source_id: "group-1", action: :delete}
           ] = ReviewPlan.destructive_resolutions(plan)
  end

  test "bulk resolution only updates entities with the requested status" do
    plan = %{lights: %{"new-light" => false, "missing-light" => false}, groups: %{}}

    statuses = %{
      lights: %{"new-light" => :new, "missing-light" => :missing},
      groups: %{}
    }

    updated = ReviewPlan.apply_bulk_resolution(plan, statuses, "missing", "disable")

    assert ReviewPlan.entity_resolution(updated, :lights, "missing-light") == "disable"
    assert ReviewPlan.entity_resolution(updated, :lights, "new-light") == nil
  end

  test "area merge defaults preserve existing-area matches" do
    normalized = %{
      areas: [
        %{
          source_id: "area-1",
          name: "Office",
          normalized_name: "office"
        }
      ],
      lights: [],
      groups: []
    }

    areas = [%Area{id: 42, name: "Office"}]

    updated = ReviewPlan.apply_area_merge_defaults(%{}, normalized, areas)

    assert ReviewPlan.area_action(updated, "area-1") == "merge"
    assert ReviewPlan.area_merge_target(updated, "area-1") == "42"
  end
end
