defmodule Hueworks.Schemas.ExternalScene do
  use Ecto.Schema
  import Ecto.Changeset

  schema "external_scenes" do
    field :source, Ecto.Enum, values: [:ha]
    field :source_id, :string
    field :name, :string
    field :display_name, :string
    field :enabled, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :bridge, Hueworks.Schemas.Bridge
    has_one :mapping, Hueworks.Schemas.ExternalSceneMapping

    timestamps()
  end

  def changeset(external_scene, attrs) do
    external_scene
    |> cast(attrs, [:bridge_id, :source, :source_id, :name, :display_name, :enabled, :metadata])
    |> validate_required([:bridge_id, :source, :source_id, :name])
    |> unique_constraint([:bridge_id, :source, :source_id])
  end
end
