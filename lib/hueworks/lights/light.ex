defmodule Hueworks.Lights.Light do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lights" do
    field(:name, :string)
    field(:source, Ecto.Enum, values: [:hue, :caseta, :ha])
    field(:source_id, :string)
    belongs_to(:bridge, Hueworks.Bridges.Bridge)
    belongs_to(:canonical_light, __MODULE__)
    field(:min_kelvin, :integer)
    field(:max_kelvin, :integer)
    field(:enabled, :boolean, default: true)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(light, attrs) do
    light
    |> cast(attrs, [
      :name,
      :source,
      :source_id,
      :bridge_id,
      :canonical_light_id,
      :min_kelvin,
      :max_kelvin,
      :enabled,
      :metadata
    ])
    |> validate_required([:name, :source, :source_id, :bridge_id])
    |> validate_change(:canonical_light_id, fn :canonical_light_id, canonical_light_id ->
      if light.id && canonical_light_id == light.id do
        [canonical_light_id: "cannot reference itself"]
      else
        []
      end
    end)
    |> unique_constraint([:bridge_id, :source_id])
  end
end
