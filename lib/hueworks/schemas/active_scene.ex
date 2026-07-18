defmodule Hueworks.Schemas.ActiveScene do
  use Ecto.Schema
  import Ecto.Changeset

  schema "active_scenes" do
    field(:last_applied_at, :utc_datetime_usec)
    field(:power_overrides, :map, default: %{})
    field(:circadian_resume_at, :utc_datetime_usec)

    belongs_to(:area, Hueworks.Schemas.Area)
    belongs_to(:scene, Hueworks.Schemas.Scene)

    timestamps()
  end

  def changeset(active_scene, attrs) do
    active_scene
    |> cast(attrs, [
      :area_id,
      :scene_id,
      :last_applied_at,
      :power_overrides,
      :circadian_resume_at
    ])
    |> validate_required([:area_id, :scene_id])
    |> unique_constraint(:area_id)
    |> foreign_key_constraint(:area_id)
    |> foreign_key_constraint(:scene_id)
  end
end
