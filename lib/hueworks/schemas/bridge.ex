defmodule Hueworks.Schemas.Bridge do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bridges" do
    field(:type, Ecto.Enum, values: [:hue, :caseta, :ha])
    field(:name, :string)
    field(:host, :string)
    field(:credentials, :map)
    field(:enabled, :boolean, default: true)
    field(:import_complete, :boolean, default: false)

    timestamps()
  end

  def changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:type, :name, :host, :credentials, :enabled, :import_complete])
    |> validate_required([:type, :name, :host, :credentials])
    |> unique_constraint([:type, :host])
  end
end
