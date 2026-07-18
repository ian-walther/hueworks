defmodule Hueworks.DomainEventsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.PresenceInputs
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{PresenceInput, Area, Scene}
  alias Phoenix.PubSub

  setup do
    PubSub.subscribe(Hueworks.PubSub, "domain_events")
    :ok
  end

  test "scene CRUD publishes domain events" do
    area = Repo.insert!(%Area{name: "Main Floor"})
    area_id = area.id

    assert {:ok, %Scene{} = scene} = Scenes.create_scene(%{name: "Morning", area_id: area.id})
    scene_id = scene.id

    assert_receive {:scene_saved, %Scene{id: ^scene_id, area_id: ^area_id}}

    assert {:ok, %Scene{} = updated} = Scenes.update_scene(scene, %{name: "Evening"})
    assert_receive {:scene_saved, %Scene{id: ^scene_id, name: "Evening"}}

    assert {:ok, %Scene{} = deleted} = Scenes.delete_scene(updated)
    assert deleted.id == scene_id
    assert_receive {:scene_deleted, %Scene{id: ^scene_id, area_id: ^area_id}}
  end

  test "presence input CRUD publishes domain events" do
    area = Repo.insert!(%Area{name: "Office"})

    assert {:ok, %PresenceInput{} = input} =
             PresenceInputs.create_input(area.id, %{name: "Desk", occupied: true})

    input_id = input.id

    assert_receive {:presence_input_changed,
                    %PresenceInput{id: ^input_id, area_id: area_id, name: "Desk"}}

    assert area_id == area.id

    assert {:ok, %PresenceInput{} = updated} =
             PresenceInputs.update_input(input, %{name: "Sitting Area"})

    assert_receive {:presence_input_changed, %PresenceInput{id: ^input_id, name: "Sitting Area"}}

    assert {:ok, %PresenceInput{} = deleted} = PresenceInputs.delete_input(updated)
    assert deleted.id == input_id
    assert_receive {:presence_input_deleted, ^input_id}
  end
end
