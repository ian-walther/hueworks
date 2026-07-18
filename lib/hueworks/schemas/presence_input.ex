defmodule Hueworks.Schemas.PresenceInput do
  use Ecto.Schema
  import Ecto.Changeset

  schema "presence_inputs" do
    field(:name, :string)
    field(:occupied, :boolean, default: false)
    field(:metadata, :map, default: %{})

    belongs_to(:area, Hueworks.Schemas.Area)

    timestamps()
  end

  def changeset(presence_input, attrs) do
    presence_input
    |> cast(attrs, [:area_id, :name, :occupied, :metadata])
    |> validate_required([:area_id, :name])
    |> validate_length(:name, min: 1, max: 120)
    |> foreign_key_constraint(:area_id)
  end
end
