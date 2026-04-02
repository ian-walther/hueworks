defmodule Hueworks.Schemas.ExternalSceneMapping do
  use Ecto.Schema
  import Ecto.Changeset

  schema "external_scene_mappings" do
    field :enabled, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :external_scene, Hueworks.Schemas.ExternalScene
    belongs_to :scene, Hueworks.Schemas.Scene

    timestamps()
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:external_scene_id, :scene_id, :enabled, :metadata])
    |> validate_required([:external_scene_id])
    |> unique_constraint([:external_scene_id])
  end
end
