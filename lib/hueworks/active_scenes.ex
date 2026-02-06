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
      brightness_override: false,
      last_applied_at: now
    }

    %ActiveScene{}
    |> ActiveScene.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          scene_id: scene.id,
          brightness_override: false,
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

  def set_brightness_override(room_id, value) when is_boolean(value) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(a in ActiveScene, where: a.room_id == ^room_id),
      set: [brightness_override: value, updated_at: now]
    )

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

  def handle_manual_change(nil, _attrs), do: :ok

  def handle_manual_change(room_id, attrs) when is_integer(room_id) and is_map(attrs) do
    if brightness_only?(attrs) do
      set_brightness_override(room_id, true)
    else
      clear_for_room(room_id)
    end
  end

  defp brightness_only?(attrs) do
    keys = Map.keys(attrs)

    keys != [] and
      Enum.all?(keys, fn key ->
        key in [:brightness, "brightness"]
      end)
  end
end
