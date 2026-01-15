defmodule Hueworks.Bridges.Bridge do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bridges" do
    field(:type, Ecto.Enum, values: [:hue, :caseta, :ha])
    field(:name, :string)
    field(:host, :string)
    field(:credentials, :map)
    field(:enabled, :boolean, default: true)

    timestamps()
  end

  def changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:type, :name, :host, :credentials, :enabled])
    |> validate_required([:type, :name, :host, :credentials])
    |> unique_constraint([:type, :host])
  end
end
