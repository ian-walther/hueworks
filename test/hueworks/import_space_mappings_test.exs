defmodule Hueworks.Import.SpaceMappingsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ExternalSpaces
  alias Hueworks.Import.{Materialize, ReimportPlan, ReviewPlan}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Area, Light}

  setup do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.home:8123",
        credentials: %{token: "token"}
      })

    %{bridge: bridge}
  end

  test "initial import persists a reviewed source-space mapping", %{bridge: bridge} do
    target = Repo.insert!(%Area{name: "Main Floor"})
    normalized = normalized_snapshot("Kitchen", [light("light.kitchen", "ha_area", "office")])

    plan = %{
      areas: %{
        "office" => %{
          "action" => "merge",
          "target_area_id" => Integer.to_string(target.id)
        }
      },
      lights: %{"light.kitchen" => true},
      groups: %{}
    }

    assert :ok = Materialize.materialize(bridge, normalized, plan)
    assert Repo.get_by!(Light, source_id: "light.kitchen").area_id == target.id
    assert ExternalSpaces.mapped_area_id(bridge, "ha_area", "office") == target.id
  end

  test "a direct HA Area mapping takes precedence over its inherited Floor mapping", %{
    bridge: bridge
  } do
    floor_area = Repo.insert!(%Area{name: "Main Floor"})
    direct_area = Repo.insert!(%Area{name: "Office"})

    {:ok, spaces} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_floor", external_id: "main", name: "Main Floor"},
        %{
          kind: "ha_area",
          external_id: "office",
          name: "Office",
          parent_kind: "ha_floor",
          parent_external_id: "main"
        }
      ])

    floor = Enum.find(spaces, &(&1.kind == "ha_floor"))
    office = Enum.find(spaces, &(&1.kind == "ha_area"))
    {:ok, _mapping} = ExternalSpaces.put_mapping(floor, floor_area)
    {:ok, _mapping} = ExternalSpaces.put_mapping(office, direct_area)

    normalized =
      normalized_snapshot(
        "Office",
        [
          %{
            light("light.desk", "ha_area", "office")
            | space_refs: [
                %{kind: "ha_area", external_id: "office", relationship: "direct"},
                %{kind: "ha_floor", external_id: "main", relationship: "inherited"}
              ]
          }
        ],
        [
          %{kind: "ha_floor", external_id: "main", source_id: "main", name: "Main Floor"},
          %{
            kind: "ha_area",
            external_id: "office",
            source_id: "office",
            name: "Office",
            parent_kind: "ha_floor",
            parent_external_id: "main"
          }
        ]
      )

    plan = %{
      areas: %{"office" => %{"action" => "skip"}},
      lights: %{"light.desk" => true},
      groups: %{}
    }

    assert :ok = Materialize.materialize(bridge, normalized, plan)
    assert Repo.get_by!(Light, source_id: "light.desk").area_id == direct_area.id
  end

  test "editing a mapping affects future imports without moving existing entities", %{
    bridge: bridge
  } do
    original_area = Repo.insert!(%Area{name: "Original"})
    future_area = Repo.insert!(%Area{name: "Future"})
    normalized = normalized_snapshot("Office", [light("light.existing", "ha_area", "office")])

    initial_plan = %{
      areas: %{
        "office" => %{
          "action" => "merge",
          "target_area_id" => Integer.to_string(original_area.id)
        }
      },
      lights: %{"light.existing" => true},
      groups: %{}
    }

    assert :ok = Materialize.materialize(bridge, normalized, initial_plan)
    existing = Repo.get_by!(Light, source_id: "light.existing")

    source_space = ExternalSpaces.get_by_identity(bridge, "ha_area", "office")
    assert {:ok, _mapping} = ExternalSpaces.put_mapping(source_space, future_area)

    reimported =
      normalized_snapshot("Renamed Office", [
        light("light.existing", "ha_area", "office"),
        light("light.new", "ha_area", "office")
      ])

    plan = %{
      areas: %{"office" => %{"action" => "skip"}},
      lights: %{
        "light.existing" => true,
        "light.new" => %{"selected" => true, "resolution" => "import"}
      },
      groups: %{}
    }

    assert :ok = Materialize.materialize(bridge, reimported, plan)
    assert Repo.get!(Light, existing.id).area_id == original_area.id
    assert Repo.get_by!(Light, source_id: "light.new").area_id == future_area.id

    renamed_space = ExternalSpaces.get_by_identity(bridge, "ha_area", "office")
    assert renamed_space.name == "Renamed Office"
  end

  test "saved mapping overrides normalized-name defaults in initial and reimport reviews", %{
    bridge: bridge
  } do
    mapped_area = Repo.insert!(%Area{name: "Main Floor"})
    same_name_area = Repo.insert!(%Area{name: "Office"})

    {:ok, [space]} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_area", external_id: "office", name: "Old Office Name"}
      ])

    {:ok, _mapping} = ExternalSpaces.put_mapping(space, mapped_area)
    normalized = normalized_snapshot("Office", [])

    initial =
      normalized
      |> default_plan()
      |> ReviewPlan.apply_area_merge_defaults(normalized, [mapped_area, same_name_area])
      |> Hueworks.Import.SpaceMappings.apply_plan_defaults(normalized)

    assert ReviewPlan.area_merge_target(initial, "office") == to_string(mapped_area.id)

    %{plan: reimport} =
      ReimportPlan.build(normalized, %{lights: [], groups: []}, [same_name_area])

    assert ReviewPlan.area_merge_target(reimport, "office") == to_string(mapped_area.id)
  end

  defp normalized_snapshot(name, lights, external_spaces \\ nil) do
    placement_space = %{
      source: :ha,
      source_id: "office",
      kind: "ha_area",
      external_id: "office",
      name: name,
      normalized_name: Hueworks.Util.normalize_area_name(name),
      metadata: %{}
    }

    %{
      schema_version: 2,
      bridge: %{id: 1, type: :ha},
      areas: [placement_space],
      external_spaces: external_spaces || [placement_space],
      lights: lights,
      groups: [],
      memberships: %{group_lights: []}
    }
  end

  defp light(source_id, kind, external_space_id) do
    %{
      source: :ha,
      source_id: source_id,
      name: source_id,
      area_source_id: external_space_id,
      space_refs: [
        %{kind: kind, external_id: external_space_id, relationship: "direct"}
      ],
      classification: "light",
      capabilities: %{},
      identifiers: %{},
      metadata: %{}
    }
  end

  defp default_plan(normalized), do: Hueworks.Import.Plan.build_default(normalized)
end
