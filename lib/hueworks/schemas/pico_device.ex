defmodule Hueworks.Schemas.PicoDevice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pico_devices" do
    field(:source_id, :string)
    field(:name, :string)
    field(:display_name, :string)
    field(:hardware_profile, :string)
    field(:enabled, :boolean, default: true)
    field(:metadata, :map, default: %{})

    belongs_to(:bridge, Hueworks.Schemas.Bridge)
    belongs_to(:room, Hueworks.Schemas.Room)
    has_many(:buttons, Hueworks.Schemas.PicoButton)

    timestamps()
  end

  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :bridge_id,
      :room_id,
      :source_id,
      :name,
      :display_name,
      :hardware_profile,
      :enabled,
      :metadata
    ])
    |> validate_required([:bridge_id, :source_id, :name, :hardware_profile])
    |> unique_constraint([:bridge_id, :source_id])
  end
end
