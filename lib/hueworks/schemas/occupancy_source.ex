defmodule Hueworks.Schemas.OccupancySource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "occupancy_sources" do
    field(:name, :string)
    field(:occupied, :boolean, default: true)
    field(:metadata, :map, default: %{})

    belongs_to(:room, Hueworks.Schemas.Room)
    has_many(:scene_components, Hueworks.Schemas.SceneComponent)

    timestamps()
  end

  def changeset(occupancy_source, attrs) do
    occupancy_source
    |> cast(attrs, [:room_id, :name, :occupied, :metadata])
    |> validate_required([:room_id, :name, :occupied])
  end
end
