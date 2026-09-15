defmodule Hueworks.Schemas.HomeKitAccessoryId do
  @moduledoc false
  # Permanent HomeKit identities for one exported entity, keyed by its serial number: the
  # accessory ID and the instance ID of each characteristic ever published for it (by HAP
  # type, plus "service" for the control service itself).

  use Ecto.Schema
  import Ecto.Changeset

  schema "homekit_accessory_ids" do
    field(:serial_number, :string)
    field(:aid, :integer)
    field(:iids, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:serial_number, :aid, :iids])
    |> validate_required([:serial_number, :aid])
    |> unique_constraint(:serial_number)
    |> unique_constraint(:aid)
  end
end
