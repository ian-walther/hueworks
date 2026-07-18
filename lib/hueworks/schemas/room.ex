defmodule Hueworks.Schemas.Room do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.PublishedIdentity

  schema "rooms" do
    field(:name, :string)
    field(:display_name, :string)
    field(:metadata, :map, default: %{})

    field(:ha_device_identifier, :string,
      autogenerate: {PublishedIdentity, :room_device_identifier, []}
    )

    field(:ha_scene_select_identifier, :string,
      autogenerate: {PublishedIdentity, :room_scene_select_identifier, []}
    )

    has_many(:lights, Hueworks.Schemas.Light)
    has_many(:groups, Hueworks.Schemas.Group)
    has_many(:scenes, Hueworks.Schemas.Scene)
    has_many(:presence_inputs, Hueworks.Schemas.PresenceInput)

    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :display_name, :metadata])
    |> put_new_published_identities()
    |> validate_required([:name])
    |> unique_constraint(:ha_device_identifier)
    |> unique_constraint(:ha_scene_select_identifier)
  end

  defp put_new_published_identities(%Ecto.Changeset{data: %__MODULE__{id: nil}} = changeset) do
    :room
    |> PublishedIdentity.space_identifiers()
    |> Enum.reduce(changeset, fn {field, value}, acc ->
      if get_field(acc, field) do
        acc
      else
        put_change(acc, field, value)
      end
    end)
  end

  defp put_new_published_identities(changeset), do: changeset
end
