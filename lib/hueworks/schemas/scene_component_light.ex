defmodule Hueworks.Schemas.SceneComponentLight do
  use Ecto.Schema
  import Ecto.Changeset

  schema "scene_component_lights" do
    field(:default_power, Ecto.Enum,
      values: [:default_on, :default_off, :follow_occupancy, :force_on, :force_off],
      default: :default_on
    )

    belongs_to(:scene_component, Hueworks.Schemas.SceneComponent)
    belongs_to(:light, Hueworks.Schemas.Light)

    timestamps()
  end

  def changeset(scene_component_light, attrs) do
    scene_component_light
    |> cast(attrs, [:scene_component_id, :light_id, :default_power])
    |> validate_required([:scene_component_id, :light_id, :default_power])
  end
end
