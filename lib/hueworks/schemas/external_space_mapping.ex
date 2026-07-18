defmodule Hueworks.Schemas.ExternalSpaceMapping do
  use Ecto.Schema
  import Ecto.Changeset

  schema "external_space_mappings" do
    belongs_to(:external_space, Hueworks.Schemas.ExternalSpace)
    belongs_to(:area, Hueworks.Schemas.Area)

    timestamps()
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:external_space_id, :area_id])
    |> validate_required([:external_space_id, :area_id])
    |> foreign_key_constraint(:external_space_id)
    |> foreign_key_constraint(:area_id)
    |> unique_constraint(:external_space_id)
  end
end
