defmodule Hueworks.PresenceInputsTest do
  use Hueworks.DataCase, async: true

  alias Hueworks.PresenceInputs
  alias Hueworks.Repo
  alias Hueworks.Schemas.{PresenceInput, Room}

  test "create_input persists a room-scoped passive boolean" do
    room = Repo.insert!(%Room{name: "Office"})

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
    room = Repo.insert!(%Room{name: "Office"})
    input = Repo.insert!(%PresenceInput{room_id: room.id, name: "Desk", occupied: true})

    assert {:ok, updated} = PresenceInputs.update_input(input, %{name: "Sitting Area"})
    assert updated.name == "Sitting Area"

    assert {:ok, deleted} = PresenceInputs.delete_input(updated)
    assert deleted.id == input.id
    refute Repo.get(PresenceInput, input.id)
  end

  test "set_occupied stores HA-driven state without touching control state" do
    room = Repo.insert!(%Room{name: "Office"})
    input = Repo.insert!(%PresenceInput{room_id: room.id, name: "Desk", occupied: true})

    assert {:ok, updated} =
             PresenceInputs.set_occupied(input.id, false, refresh_home_assistant: false)

    assert updated.occupied == false
    assert Repo.get!(PresenceInput, input.id).occupied == false
  end
end
