defmodule Hueworks.CircadianPollerTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.CircadianPoller
  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Room, Scene}

  defp insert_room do
    Repo.insert!(%Room{name: "Studio", metadata: %{}})
  end

  defp insert_scene(room) do
    Repo.insert!(%Scene{name: "Chill", room_id: room.id, metadata: %{}})
  end

  test "poller reapplies active scenes immediately on startup" do
    room = insert_room()
    scene = insert_scene(room)

    {:ok, _} = ActiveScenes.set_active(scene)
    active = Repo.get_by!(ActiveScene, room_id: room.id)
    stale_last_applied_at = DateTime.add(DateTime.utc_now(), -5, :minute)

    active
    |> Ecto.Changeset.change(last_applied_at: stale_last_applied_at)
    |> Repo.update!()

    {:ok, pid} = CircadianPoller.start_link(name: nil, interval_ms: 60_000)

    assert eventually(fn ->
             refreshed = Repo.get_by!(ActiveScene, room_id: room.id)
             DateTime.compare(refreshed.last_applied_at, stale_last_applied_at) == :gt
           end)

    GenServer.stop(pid)
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
