defmodule Hueworks.OccupancyTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState
  alias Hueworks.Occupancy
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Scenes

  alias Hueworks.Schemas.{
    Light,
    OccupancySource,
    Room
  }

  defp insert_room(attrs) do
    defaults = %{name: "Studio", metadata: %{}, occupied: true}
    Repo.insert!(struct(Room, Map.merge(defaults, attrs)))
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

  test "set_room_occupied creates and updates the default source" do
    room = insert_room(%{occupied: true})

    assert :ok = Rooms.set_occupied(room.id, false)

    source = Occupancy.default_source_for_room(room.id)
    room = Repo.get!(Room, room.id)

    assert source.name == Occupancy.default_source_name()
    assert source.occupied == false
    assert room.occupied == false
    assert Rooms.room_occupied?(room.id) == false

    assert :ok = Rooms.set_occupied(room.id, true)

    assert Occupancy.default_source_for_room(room.id).occupied == true
    assert Repo.get!(Room, room.id).occupied == true
  end

  test "set_source_occupied syncs default source back to room occupancy" do
    room = insert_room(%{occupied: true})
    :ok = Rooms.set_occupied(room.id, true)
    source = Occupancy.default_source_for_room(room.id)

    assert {:ok, updated} =
             Occupancy.set_source_occupied(source.id, false, reapply_active_scene: false)

    assert updated.occupied == false
    assert Repo.get!(Room, room.id).occupied == false
    assert Rooms.room_occupied?(room.id) == false
  end

  test "delete_source refuses to delete the default room occupancy source" do
    room = insert_room(%{occupied: true})
    :ok = Rooms.set_occupied(room.id, true)
    source = Occupancy.default_source_for_room(room.id)

    assert {:error, :default_source} = Occupancy.delete_source(source)
    assert Repo.get(OccupancySource, source.id)
  end

  test "set_source_occupied reapplies the active scene for source-backed components" do
    room = insert_room(%{occupied: true})
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Desk Lamp"})
    source = Repo.insert!(%OccupancySource{room_id: room.id, name: "Desk", occupied: true})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Work", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Desk",
          light_ids: [light.id],
          light_state_id: to_string(state.id),
          occupancy_source_id: to_string(source.id),
          light_defaults: %{light.id => :follow_occupancy}
        }
      ])

    {:ok, _active} = ActiveScenes.set_active(scene)
    {:ok, _diff, _updated} = Scenes.apply_scene(scene)
    assert DesiredState.get(:light, light.id)[:power] == :on

    assert {:ok, _source} = Occupancy.set_source_occupied(source.id, false)

    assert DesiredState.get(:light, light.id)[:power] == :off
  end
end
