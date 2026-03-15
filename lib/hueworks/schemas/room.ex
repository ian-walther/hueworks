defmodule Hueworks.Schemas.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rooms" do
    field(:name, :string)
    field(:display_name, :string)
    field(:occupied, :boolean, default: true)
    field(:metadata, :map, default: %{})

    has_many(:lights, Hueworks.Schemas.Light)
    has_many(:groups, Hueworks.Schemas.Group)
    has_many(:scenes, Hueworks.Schemas.Scene)

    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :display_name, :occupied, :metadata])
    |> validate_required([:name])
  end
end
