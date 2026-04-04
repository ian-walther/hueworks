defmodule Hueworks.ActiveScenes do
  @moduledoc """
  Tracks the active scene per room for circadian/manual polling.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Scene}

  def list_active_scenes do
    Repo.all(from(a in ActiveScene, select: a))
  end

  def get_for_room(room_id) do
    Repo.one(from(a in ActiveScene, where: a.room_id == ^room_id))
  end

  def set_active(%Scene{} = scene) do
    now = DateTime.utc_now()

    attrs = %{
      room_id: scene.room_id,
      scene_id: scene.id,
      last_applied_at: now
    }

    %ActiveScene{}
    |> ActiveScene.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          scene_id: scene.id,
          last_applied_at: now,
          updated_at: now
        ]
      ],
      conflict_target: :room_id
    )
  end

  def clear_for_room(room_id) do
    Repo.delete_all(from(a in ActiveScene, where: a.room_id == ^room_id))
    :ok
  end

  def deactivate_scene(scene_id) when is_integer(scene_id) do
    Repo.delete_all(from(a in ActiveScene, where: a.scene_id == ^scene_id))
    :ok
  end

  def mark_applied(%ActiveScene{id: id}) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(a in ActiveScene, where: a.id == ^id),
      set: [last_applied_at: now, updated_at: now]
    )

    :ok
  end
end
