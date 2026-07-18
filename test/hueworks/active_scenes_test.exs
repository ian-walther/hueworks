defmodule Hueworks.ActiveScenesTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.TraceBuffer
  alias Phoenix.PubSub
  alias Hueworks.Repo
  alias Hueworks.Scenes.Apply, as: SceneApply
  alias Hueworks.Schemas.{ActiveScene, Area, Scene}

  defp insert_area do
    Repo.insert!(%Area{name: "Studio", metadata: %{}})
  end

  defp insert_scene(area, name) do
    Repo.insert!(%Scene{name: name, area_id: area.id, metadata: %{}})
  end

  test "set_active upserts by area" do
    area = insert_area()
    scene1 = insert_scene(area, "Chill")
    scene2 = insert_scene(area, "Focus")

    {:ok, _} = ActiveScenes.set_active(scene1)

    active = Repo.get_by(ActiveScene, area_id: area.id)
    assert active.scene_id == scene1.id
    assert %DateTime{} = active.last_applied_at

    {:ok, _} = ActiveScenes.set_active(scene2)

    active = Repo.get_by(ActiveScene, area_id: area.id)
    assert active.scene_id == scene2.id
    assert %DateTime{} = active.last_applied_at
    assert Repo.aggregate(ActiveScene, :count) == 1
  end

  test "set_active persists and replaces the circadian deferral deadline" do
    area = insert_area()
    scene1 = insert_scene(area, "Chill")
    scene2 = insert_scene(area, "Focus")
    now = ~U[2026-07-11 20:00:00.000000Z]
    resume_at = DateTime.add(now, 30_000, :millisecond)

    assert {:ok, _} =
             ActiveScenes.set_active(scene1, now: now, circadian_resume_at: resume_at)

    active = ActiveScenes.get_for_area(area.id)
    assert active.circadian_resume_at == resume_at
    assert ActiveScenes.circadian_deferred?(active, now)
    assert ActiveScenes.remaining_circadian_deferral_ms(active, now) == 30_000

    assert {:ok, _} = ActiveScenes.set_active(scene2, now: now)

    refute ActiveScenes.get_for_area(area.id).circadian_resume_at
  end

  test "mark_applied refreshes last_applied_at" do
    area = insert_area()
    scene = insert_scene(area, "Chill")
    {:ok, _} = ActiveScenes.set_active(scene)
    active_before = Repo.get_by!(ActiveScene, area_id: area.id)
    Process.sleep(5)

    :ok = ActiveScenes.mark_applied(active_before)

    active_after = Repo.get_by!(ActiveScene, area_id: area.id)
    assert DateTime.compare(active_after.last_applied_at, active_before.last_applied_at) == :gt
  end

  test "deactivate_scene removes active row for that scene" do
    area = insert_area()
    scene = insert_scene(area, "Chill")
    {:ok, _} = ActiveScenes.set_active(scene)

    :ok = ActiveScenes.deactivate_scene(scene.id)

    refute Repo.get_by(ActiveScene, area_id: area.id)
  end

  test "active scene changes are broadcast" do
    area = insert_area()
    scene = insert_scene(area, "Chill")
    area_id = area.id
    scene_id = scene.id
    PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())

    {:ok, _} = ActiveScenes.set_active(scene)
    assert_receive {:active_scene_updated, ^area_id, ^scene_id}

    :ok = ActiveScenes.clear_for_area(area.id)
    assert_receive {:active_scene_updated, ^area_id, nil}
  end

  test "scene activation does not apply intent when active-scene persistence fails" do
    area = insert_area()
    scene = insert_scene(area, "Deleted Area Scene")
    trace = %{trace_id: "failed-active-scene", source: "test"}
    TraceBuffer.clear()
    Repo.delete!(area)

    assert {:error, changeset} = SceneApply.activate_scene(scene, trace: trace)

    assert Keyword.has_key?(changeset.errors, :base)

    assert ActiveScenes.get_for_area(area.id) == nil
    assert TraceBuffer.recent(trace_id: trace.trace_id).events == []
  end
end
