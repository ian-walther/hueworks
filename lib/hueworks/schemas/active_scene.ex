defmodule Hueworks.Schemas.ActiveScene do
  use Ecto.Schema
  import Ecto.Changeset

  schema "active_scenes" do
    field(:last_applied_at, :utc_datetime_usec)
    field(:power_overrides, :map, default: %{})

    belongs_to(:room, Hueworks.Schemas.Room)
    belongs_to(:scene, Hueworks.Schemas.Scene)

    timestamps()
  end

  def changeset(active_scene, attrs) do
    active_scene
    |> cast(attrs, [
      :room_id,
      :scene_id,
      :last_applied_at,
      :power_overrides
    ])
    |> validate_required([:room_id, :scene_id])
  end
end
