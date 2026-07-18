defmodule Hueworks.Schemas.ExternalSpace do
  use Ecto.Schema
  import Ecto.Changeset

  schema "external_spaces" do
    field(:kind, :string)
    field(:external_id, :string)
    field(:name, :string)
    field(:metadata, :map, default: %{})
    field(:last_seen_at, :utc_datetime_usec)

    belongs_to(:bridge, Hueworks.Schemas.Bridge)
    belongs_to(:parent_external_space, __MODULE__)
    has_many(:child_external_spaces, __MODULE__, foreign_key: :parent_external_space_id)
    has_one(:mapping, Hueworks.Schemas.ExternalSpaceMapping)

    timestamps()
  end

  def changeset(external_space, attrs) do
    external_space
    |> cast(attrs, [
      :bridge_id,
      :parent_external_space_id,
      :kind,
      :external_id,
      :name,
      :metadata,
      :last_seen_at
    ])
    |> validate_required([:bridge_id, :kind, :external_id, :name, :last_seen_at])
    |> validate_length(:kind, max: 80)
    |> validate_length(:external_id, max: 512)
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:bridge_id)
    |> foreign_key_constraint(:parent_external_space_id)
    |> unique_constraint([:bridge_id, :kind, :external_id])
  end
end
