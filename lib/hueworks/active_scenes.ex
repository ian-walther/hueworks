defmodule Hueworks.ActiveScenes do
  @moduledoc """
  Tracks the active scene per room for circadian/manual polling.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Scene}

  @default_pending_grace_ms 3_000

  def list_active_scenes do
    Repo.all(from(a in ActiveScene, select: a))
  end

  def get_for_room(room_id) do
    Repo.one(from(a in ActiveScene, where: a.room_id == ^room_id))
  end

  def set_active(%Scene{} = scene) do
    now = DateTime.utc_now()
    pending_until = DateTime.add(now, pending_grace_ms(), :millisecond)

    attrs = %{
      room_id: scene.room_id,
      scene_id: scene.id,
      brightness_override: false,
      occupied: true,
      last_applied_at: now,
      pending_until: pending_until
    }

    %ActiveScene{}
    |> ActiveScene.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          scene_id: scene.id,
          brightness_override: false,
          occupied: true,
          last_applied_at: now,
          pending_until: pending_until,
          updated_at: now
        ]
      ],
      conflict_target: :room_id
    )
  end

  def pending_for_room?(room_id, now \\ DateTime.utc_now()) when is_integer(room_id) do
    case get_for_room(room_id) do
      %ActiveScene{pending_until: %DateTime{} = pending_until} ->
        DateTime.compare(pending_until, now) == :gt

      _ ->
        false
    end
  end

  def clear_for_room(room_id) do
    Repo.delete_all(from(a in ActiveScene, where: a.room_id == ^room_id))
    :ok
  end

  def deactivate_scene(scene_id) when is_integer(scene_id) do
    Repo.delete_all(from(a in ActiveScene, where: a.scene_id == ^scene_id))
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

  def set_occupied(room_id, value) when is_integer(room_id) and is_boolean(value) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(a in ActiveScene, where: a.room_id == ^room_id),
      set: [occupied: value, updated_at: now]
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
    if brightness_or_power_only?(attrs) do
      set_brightness_override(room_id, true)
    else
      clear_for_room(room_id)
    end
  end

  defp brightness_or_power_only?(attrs) do
    keys = Map.keys(attrs)

    keys != [] and
      Enum.all?(keys, fn key ->
        key in [:brightness, "brightness", :power, "power"]
      end)
  end

  defp pending_grace_ms do
    Application.get_env(:hueworks, :scene_activation_pending_ms, @default_pending_grace_ms)
  end
end
