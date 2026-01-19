defmodule Hueworks.Schemas.SceneComponent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "scene_components" do
    field(:name, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:scene, Hueworks.Schemas.Scene)
    belongs_to(:light_state, Hueworks.Schemas.LightState)
    has_many(:scene_component_lights, Hueworks.Schemas.SceneComponentLight)
    has_many(:lights, through: [:scene_component_lights, :light])

    timestamps()
  end

  def changeset(scene_component, attrs) do
    scene_component
    |> cast(attrs, [:name, :metadata, :scene_id, :light_state_id])
    |> validate_required([:scene_id, :light_state_id])
  end
end
