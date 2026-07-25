defmodule Hueworks.Schemas.ExternalSpaceIgnore do
  use Ecto.Schema
  import Ecto.Changeset

  schema "external_space_ignores" do
    belongs_to(:external_space, Hueworks.Schemas.ExternalSpace)

    timestamps()
  end

  def changeset(ignore, attrs) do
    ignore
    |> cast(attrs, [:external_space_id])
    |> validate_required([:external_space_id])
    |> foreign_key_constraint(:external_space_id)
    |> unique_constraint(:external_space_id)
  end
end
