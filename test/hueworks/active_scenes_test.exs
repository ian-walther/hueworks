defmodule Hueworks.ActiveScenesTest do
  use Hueworks.DataCase, async: false
  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Room, Scene}

  defp insert_room do
    Repo.insert!(%Room{name: "Studio", metadata: %{}})
  end

  defp insert_scene(room, name) do
    Repo.insert!(%Scene{name: name, room_id: room.id, metadata: %{}})
  end

  test "set_active upserts by room and resets overrides" do
    room = insert_room()
    scene1 = insert_scene(room, "Chill")
    scene2 = insert_scene(room, "Focus")

    {:ok, _} = ActiveScenes.set_active(scene1)

    active = Repo.get_by(ActiveScene, room_id: room.id)
    assert active.scene_id == scene1.id
    refute active.brightness_override
    assert %DateTime{} = active.pending_until
    assert DateTime.compare(active.pending_until, DateTime.utc_now()) == :gt

    {:ok, _} = ActiveScenes.set_active(scene2)

    active = Repo.get_by(ActiveScene, room_id: room.id)
    assert active.scene_id == scene2.id
    refute active.brightness_override
    assert %DateTime{} = active.pending_until
    assert DateTime.compare(active.pending_until, DateTime.utc_now()) == :gt
    assert Repo.aggregate(ActiveScene, :count) == 1
  end

  test "handle_manual_change marks brightness overrides" do
    room = insert_room()
    scene = insert_scene(room, "Chill")
    {:ok, _} = ActiveScenes.set_active(scene)

    :ok = ActiveScenes.handle_manual_change(room.id, %{brightness: 45})

    active = Repo.get_by(ActiveScene, room_id: room.id)
    assert active.brightness_override
  end

  test "handle_manual_change clears active scenes for non-brightness changes" do
    room = insert_room()
    scene = insert_scene(room, "Chill")
    {:ok, _} = ActiveScenes.set_active(scene)

    :ok = ActiveScenes.handle_manual_change(room.id, %{kelvin: 3000})

    refute Repo.get_by(ActiveScene, room_id: room.id)
  end

  test "handle_manual_change marks brightness override for power changes" do
    room = insert_room()
    scene = insert_scene(room, "Chill")
    {:ok, _} = ActiveScenes.set_active(scene)

    :ok = ActiveScenes.handle_manual_change(room.id, %{power: :off})

    active = Repo.get_by(ActiveScene, room_id: room.id)
    assert active.brightness_override
  end

  test "deactivate_scene removes active row for that scene" do
    room = insert_room()
    scene = insert_scene(room, "Chill")
    {:ok, _} = ActiveScenes.set_active(scene)

    :ok = ActiveScenes.deactivate_scene(scene.id)

    refute Repo.get_by(ActiveScene, room_id: room.id)
  end

  test "set_occupied refreshes pending grace window" do
    room = insert_room()
    scene = insert_scene(room, "Night")
    {:ok, _} = ActiveScenes.set_active(scene)

    stale_pending = DateTime.add(DateTime.utc_now(), -10, :second)

    Repo.update_all(
      from(a in ActiveScene, where: a.room_id == ^room.id),
      set: [pending_until: stale_pending]
    )

    :ok = ActiveScenes.set_occupied(room.id, false)

    after_row = Repo.get_by(ActiveScene, room_id: room.id)
    assert after_row.occupied == false
    assert DateTime.compare(after_row.pending_until, DateTime.utc_now()) == :gt
    assert ActiveScenes.pending_for_room?(room.id)
  end
end
