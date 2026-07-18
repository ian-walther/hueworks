defmodule Hueworks.ExternalSpacesTest do
  use Hueworks.DataCase, async: true

  alias Hueworks.ExternalSpaces
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Area, ExternalSpace, ExternalSpaceMapping}

  setup do
    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.home:8123",
        credentials: %{token: "token"}
      })

    area = Repo.insert!(%Area{name: "Main Floor"})
    %{bridge: bridge, area: area}
  end

  test "synchronizes source identity, hierarchy, and current source names", %{bridge: bridge} do
    seen_at = ~U[2026-07-17 12:00:00.000000Z]

    assert {:ok, spaces} =
             ExternalSpaces.sync_bridge_spaces(
               bridge,
               [
                 %{kind: "ha_floor", external_id: "floor-1", name: "First Floor"},
                 %{
                   kind: "ha_area",
                   external_id: "area-1",
                   name: "Kitchen",
                   parent_kind: "ha_floor",
                   parent_external_id: "floor-1",
                   metadata: %{aliases: ["Cooking"]}
                 }
               ],
               seen_at: seen_at
             )

    kitchen = Enum.find(spaces, &(&1.external_id == "area-1"))
    assert kitchen.kind == "ha_area"
    assert kitchen.name == "Kitchen"
    assert kitchen.metadata == %{"aliases" => ["Cooking"]}
    assert kitchen.last_seen_at == seen_at
    assert kitchen.parent_external_space.external_id == "floor-1"
  end

  test "source renames refresh facts without breaking the user mapping", %{
    bridge: bridge,
    area: area
  } do
    {:ok, _spaces} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_area", external_id: "stable-1", name: "Kitchen"}
      ])

    space = ExternalSpaces.get_by_identity(bridge, "ha_area", "stable-1")
    assert {:ok, _mapping} = ExternalSpaces.put_mapping(space, area)

    {:ok, _spaces} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_area", external_id: "stable-1", name: "Kitchen and Dining"}
      ])

    renamed = ExternalSpaces.get_by_identity(bridge, "ha_area", "stable-1")
    assert renamed.id == space.id
    assert renamed.name == "Kitchen and Dining"
    assert ExternalSpaces.mapped_area_id(bridge, "ha_area", "stable-1") == area.id
  end

  test "many source spaces may map to one Area while each source space has one destination", %{
    bridge: bridge,
    area: area
  } do
    {:ok, spaces} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_area", external_id: "kitchen", name: "Kitchen"},
        %{kind: "ha_area", external_id: "living", name: "Living Room"}
      ])

    Enum.each(spaces, fn space ->
      assert {:ok, _mapping} = ExternalSpaces.put_mapping(space, area)
    end)

    assert Repo.aggregate(ExternalSpaceMapping, :count) == 2

    other_area = Repo.insert!(%Area{name: "Upstairs"})
    kitchen = Enum.find(spaces, &(&1.external_id == "kitchen"))
    assert {:ok, mapping} = ExternalSpaces.put_mapping(kitchen, other_area)
    assert mapping.area_id == other_area.id
    assert Repo.aggregate(ExternalSpaceMapping, :count) == 2
  end

  test "an omitted source space and its mapping remain inspectable", %{
    bridge: bridge,
    area: area
  } do
    first_seen = ~U[2026-07-17 12:00:00.000000Z]
    later_seen = ~U[2026-07-17 13:00:00.000000Z]

    {:ok, _spaces} =
      ExternalSpaces.sync_bridge_spaces(
        bridge,
        [%{kind: "ha_area", external_id: "office", name: "Office"}],
        seen_at: first_seen
      )

    office = ExternalSpaces.get_by_identity(bridge, "ha_area", "office")
    {:ok, _mapping} = ExternalSpaces.put_mapping(office, area)

    assert {:ok, spaces} = ExternalSpaces.sync_bridge_spaces(bridge, [], seen_at: later_seen)
    assert [%ExternalSpace{id: id}] = spaces
    assert id == office.id
    assert ExternalSpaces.stale?(office, later_seen)
    assert ExternalSpaces.mapped_area_id(bridge, "ha_area", "office") == area.id
  end

  test "identity is scoped by bridge and kind", %{bridge: bridge} do
    second_bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue",
        host: "hue.home",
        credentials: %{api_key: "key"}
      })

    for {owner, kind} <- [
          {bridge, "ha_area"},
          {bridge, "ha_floor"},
          {second_bridge, "hue_area"}
        ] do
      assert {:ok, _spaces} =
               ExternalSpaces.sync_bridge_spaces(owner, [
                 %{kind: kind, external_id: "shared", name: "Shared"}
               ])
    end

    assert Repo.aggregate(ExternalSpace, :count) == 3
  end

  test "deleting an Area removes its mapping but retains the source space", %{
    bridge: bridge,
    area: area
  } do
    {:ok, [space]} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_area", external_id: "office", name: "Office"}
      ])

    {:ok, _mapping} = ExternalSpaces.put_mapping(space, area)
    Repo.delete!(area)

    assert Repo.get!(ExternalSpace, space.id)
    refute Repo.get_by(ExternalSpaceMapping, external_space_id: space.id)
  end

  test "deleting a bridge intentionally removes its source spaces and mappings", %{
    bridge: bridge,
    area: area
  } do
    {:ok, [space]} =
      ExternalSpaces.sync_bridge_spaces(bridge, [
        %{kind: "ha_area", external_id: "office", name: "Office"}
      ])

    {:ok, _mapping} = ExternalSpaces.put_mapping(space, area)
    Repo.delete!(bridge)

    refute Repo.get(ExternalSpace, space.id)
    refute Repo.get_by(ExternalSpaceMapping, external_space_id: space.id)
  end
end
