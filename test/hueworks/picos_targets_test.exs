defmodule Hueworks.PicosTargetsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Picos.Targets
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, Room, Scene}

  defp insert_room(name) do
    Repo.insert!(%Room{name: name, metadata: %{}})
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

  defp insert_light(room, bridge, attrs) do
    defaults = %{
      name: "Light",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{}
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  test "expand_room_targets keeps only room-local, non-linked light targets" do
    bridge = insert_bridge()
    room = insert_room("Kitchen")
    other_room = insert_room("Other")

    direct_light = insert_light(room, bridge, %{name: "Direct"})
    grouped_light = insert_light(room, bridge, %{name: "Grouped"})
    linked_light = insert_light(room, bridge, %{name: "Linked", canonical_light_id: direct_light.id})
    other_room_light = insert_light(other_room, bridge, %{name: "Other"})

    group =
      Repo.insert!(%Group{
        name: "Kitchen Group",
        source: :hue,
        source_id: "kitchen-group",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    other_group =
      Repo.insert!(%Group{
        name: "Other Group",
        source: :hue,
        source_id: "other-group",
        bridge_id: bridge.id,
        room_id: other_room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: grouped_light.id})
    Repo.insert!(%GroupLight{group_id: other_group.id, light_id: other_room_light.id})

    assert Targets.expand_room_targets(
             room.id,
             [group.id, other_group.id],
             [direct_light.id, linked_light.id, other_room_light.id]
           ) == [grouped_light.id, direct_light.id]
  end

  test "valid_room_targets? rejects groups or lights from other rooms and linked lights" do
    bridge = insert_bridge()
    room = insert_room("Kitchen")
    other_room = insert_room("Other")

    light = insert_light(room, bridge, %{name: "Direct"})
    linked_light = insert_light(room, bridge, %{name: "Linked", canonical_light_id: light.id})
    other_light = insert_light(other_room, bridge, %{name: "Other"})

    group =
      Repo.insert!(%Group{
        name: "Kitchen Group",
        source: :hue,
        source_id: "kitchen-group",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    other_group =
      Repo.insert!(%Group{
        name: "Other Group",
        source: :hue,
        source_id: "other-group",
        bridge_id: bridge.id,
        room_id: other_room.id,
        enabled: true
      })

    assert Targets.valid_room_targets?(room.id, [group.id], [light.id])
    refute Targets.valid_room_targets?(room.id, [other_group.id], [light.id])
    refute Targets.valid_room_targets?(room.id, [group.id], [linked_light.id])
    refute Targets.valid_room_targets?(room.id, [group.id], [other_light.id])
  end

  test "scene_name_for_target scopes lookup to the room" do
    room = insert_room("Kitchen")
    other_room = insert_room("Other")

    scene = Repo.insert!(%Scene{name: "Evening", room_id: room.id, metadata: %{}})
    _other_scene = Repo.insert!(%Scene{name: "Evening", room_id: other_room.id, metadata: %{}})

    assert Targets.scene_name_for_target(scene.id, room.id) == "Evening"
    assert Targets.scene_name_for_target(scene.id, other_room.id) == "Unknown Scene"
  end
end
