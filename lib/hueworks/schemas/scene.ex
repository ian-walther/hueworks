defmodule Hueworks.Schemas.Scene do
  use Ecto.Schema
  import Ecto.Changeset

  schema "scenes" do
    field(:name, :string)
    field(:display_name, :string)
    field(:metadata, :map, default: %{})
    field(:activation_transition_ms, :integer)

    belongs_to(:area, Hueworks.Schemas.Area)
    has_many(:scene_components, Hueworks.Schemas.SceneComponent)

    timestamps()
  end

  def changeset(scene, attrs) do
    scene
    |> cast(attrs, [:name, :display_name, :metadata, :area_id, :activation_transition_ms])
    |> validate_required([:name, :area_id])
    |> validate_number(:activation_transition_ms, greater_than: 0)
  end
end
