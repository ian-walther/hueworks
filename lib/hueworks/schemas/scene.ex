defmodule Hueworks.Schemas.Scene do
  use Ecto.Schema
  import Ecto.Changeset

  schema "scenes" do
    field(:name, :string)
    field(:display_name, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:room, Hueworks.Schemas.Room)
    has_many(:scene_components, Hueworks.Schemas.SceneComponent)

    timestamps()
  end

  def changeset(scene, attrs) do
    scene
    |> cast(attrs, [:name, :display_name, :metadata, :room_id])
    |> validate_required([:name, :room_id])
  end
end
