defmodule Hueworks.PicosTargetsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Picos.Targets
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, Area, Scene}

  defp insert_area(name) do
    Repo.insert!(%Area{name: name, metadata: %{}})
  end

  defp insert_bridge do
    insert_bridge!(%{
      type: :hue,
      name: "Hue Bridge",
      host: "10.0.0.230",
      credentials: %{"api_key" => "key"},
      import_complete: false,
      enabled: true
    })
  end

  defp insert_light(area, bridge, attrs) do
    defaults = %{
      name: "Light",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      area_id: area.id,
      metadata: %{}
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  test "expand_area_targets keeps only area-local, non-linked light targets" do
    bridge = insert_bridge()
    area = insert_area("Kitchen")
    other_area = insert_area("Other")

    direct_light = insert_light(area, bridge, %{name: "Direct"})
    grouped_light = insert_light(area, bridge, %{name: "Grouped"})

    linked_light =
      insert_light(area, bridge, %{name: "Linked", canonical_light_id: direct_light.id})

    other_area_light = insert_light(other_area, bridge, %{name: "Other"})

    group =
      Repo.insert!(%Group{
        name: "Kitchen Group",
        source: :hue,
        source_id: "kitchen-group",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    other_group =
      Repo.insert!(%Group{
        name: "Other Group",
        source: :hue,
        source_id: "other-group",
        bridge_id: bridge.id,
        area_id: other_area.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: grouped_light.id})
    Repo.insert!(%GroupLight{group_id: other_group.id, light_id: other_area_light.id})

    assert Targets.expand_area_targets(
             area.id,
             [group.id, other_group.id],
             [direct_light.id, linked_light.id, other_area_light.id]
           ) == [grouped_light.id, direct_light.id]
  end

  test "valid_area_targets? rejects groups or lights from other areas and linked lights" do
    bridge = insert_bridge()
    area = insert_area("Kitchen")
    other_area = insert_area("Other")

    light = insert_light(area, bridge, %{name: "Direct"})
    linked_light = insert_light(area, bridge, %{name: "Linked", canonical_light_id: light.id})
    other_light = insert_light(other_area, bridge, %{name: "Other"})

    group =
      Repo.insert!(%Group{
        name: "Kitchen Group",
        source: :hue,
        source_id: "kitchen-group",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    other_group =
      Repo.insert!(%Group{
        name: "Other Group",
        source: :hue,
        source_id: "other-group",
        bridge_id: bridge.id,
        area_id: other_area.id,
        enabled: true
      })

    assert Targets.valid_area_targets?(area.id, [group.id], [light.id])
    refute Targets.valid_area_targets?(area.id, [other_group.id], [light.id])
    refute Targets.valid_area_targets?(area.id, [group.id], [linked_light.id])
    refute Targets.valid_area_targets?(area.id, [group.id], [other_light.id])
  end

  test "scene_name_for_target scopes lookup to the area" do
    area = insert_area("Kitchen")
    other_area = insert_area("Other")

    scene = Repo.insert!(%Scene{name: "Evening", area_id: area.id, metadata: %{}})
    _other_scene = Repo.insert!(%Scene{name: "Evening", area_id: other_area.id, metadata: %{}})

    assert Targets.scene_name_for_target(scene.id, area.id) == "Evening"
    assert Targets.scene_name_for_target(scene.id, other_area.id) == "Unknown Scene"
  end
end
