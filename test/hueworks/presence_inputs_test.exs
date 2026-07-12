defmodule Hueworks.PresenceInputsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState
  alias Hueworks.PresenceInputs
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Light, PresenceInput, Room}

  defp insert_room do
    Repo.insert!(%Room{name: "Office"})
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

  test "create_input persists a room-scoped boolean" do
    room = insert_room()

    assert {:ok, input} =
             PresenceInputs.create_input(room.id, %{
               name: "Desk Presence",
               occupied: false,
               metadata: %{}
             })

    assert input.room_id == room.id
    assert input.name == "Desk Presence"
    assert input.occupied == false
  end

  test "update_input and delete_input manage ordinary presence inputs" do
    room = insert_room()
    input = Repo.insert!(%PresenceInput{room_id: room.id, name: "Desk", occupied: true})

    assert {:ok, updated} = PresenceInputs.update_input(input, %{name: "Sitting Area"})
    assert updated.name == "Sitting Area"

    assert {:ok, deleted} = PresenceInputs.delete_input(updated)
    assert deleted.id == input.id
    refute Repo.get(PresenceInput, input.id)
  end

  test "set_occupied stores HA-driven state" do
    room = insert_room()
    input = Repo.insert!(%PresenceInput{room_id: room.id, name: "Desk", occupied: true})

    assert {:ok, updated} =
             PresenceInputs.set_occupied(input.id, false, refresh_home_assistant: false)

    assert updated.occupied == false
    assert Repo.get!(PresenceInput, input.id).occupied == false
  end

  test "set_occupied reapplies the active room scene when follow presence is used" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Desk Lamp"})

    input =
      Repo.insert!(%PresenceInput{
        room_id: room.id,
        name: "Desk Presence",
        occupied: true
      })

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Work", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light.id],
          light_state_id: to_string(state.id),
          light_defaults: %{light.id => :follow_presence},
          light_presence_inputs: %{light.id => input.id}
        }
      ])

    {:ok, _diff, _updated} = Scenes.activate_scene(scene.id)
    assert DesiredState.get(:light, light.id)[:power] == :on

    assert {:ok, updated} =
             PresenceInputs.set_occupied(input.id, false, refresh_home_assistant: false)

    assert updated.occupied == false
    assert DesiredState.get(:light, light.id)[:power] == :off
  end

  test "set_occupied can turn a follow-presence light back on after vacancy" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Desk Lamp"})

    input =
      Repo.insert!(%PresenceInput{
        room_id: room.id,
        name: "Desk Presence",
        occupied: false
      })

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Work", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light.id],
          light_state_id: to_string(state.id),
          light_defaults: %{light.id => :follow_presence},
          light_presence_inputs: %{light.id => input.id}
        }
      ])

    {:ok, _diff, _updated} = Scenes.activate_scene(scene.id)
    assert DesiredState.get(:light, light.id)[:power] == :off

    assert {:ok, updated} =
             PresenceInputs.set_occupied(input.id, true, refresh_home_assistant: false)

    assert updated.occupied == true
    assert DesiredState.get(:light, light.id)[:power] == :on
  end

  test "a presence input change leaves lights tied to other inputs untouched" do
    room = insert_room()
    bridge = insert_bridge()
    desk_light = insert_light(room, bridge, %{name: "Desk Lamp"})
    sitting_light = insert_light(room, bridge, %{name: "Sitting Lamp"})

    desk_input =
      Repo.insert!(%PresenceInput{room_id: room.id, name: "Desk Presence", occupied: true})

    sitting_input =
      Repo.insert!(%PresenceInput{room_id: room.id, name: "Sitting Presence", occupied: true})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Work", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [desk_light.id, sitting_light.id],
          light_state_id: to_string(state.id),
          light_defaults: %{
            desk_light.id => :follow_presence,
            sitting_light.id => :follow_presence
          },
          light_presence_inputs: %{
            desk_light.id => desk_input.id,
            sitting_light.id => sitting_input.id
          }
        }
      ])

    {:ok, _diff, _updated} = Scenes.activate_scene(scene.id)
    _ = DesiredState.put(:light, sitting_light.id, %{power: :on, brightness: 99})

    resume_at = DateTime.add(DateTime.utc_now(), 60, :second)
    {:ok, _} = ActiveScenes.set_active(scene, circadian_resume_at: resume_at)

    assert {:ok, updated} =
             PresenceInputs.set_occupied(desk_input.id, false, refresh_home_assistant: false)

    assert updated.occupied == false
    assert DesiredState.get(:light, desk_light.id)[:power] == :off

    assert DesiredState.get(:light, sitting_light.id) == %{
             power: :on,
             brightness: 99,
             kelvin: 3000
           }

    assert ActiveScenes.get_for_room(room.id).circadian_resume_at == resume_at
  end
end
