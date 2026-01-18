defmodule Hueworks.Schemas.Light do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lights" do
    field(:name, :string)
    field(:display_name, :string)
    field(:source, Ecto.Enum, values: [:hue, :caseta, :ha])
    field(:source_id, :string)
    belongs_to(:bridge, Hueworks.Schemas.Bridge)
    belongs_to(:canonical_light, __MODULE__)
    field(:reported_min_kelvin, :integer)
    field(:reported_max_kelvin, :integer)
    field(:actual_min_kelvin, :integer)
    field(:actual_max_kelvin, :integer)
    field(:supports_color, :boolean, default: false)
    field(:supports_temp, :boolean, default: false)
    field(:enabled, :boolean, default: true)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(light, attrs) do
    light
    |> cast(attrs, [
      :name,
      :display_name,
      :source,
      :source_id,
      :bridge_id,
      :canonical_light_id,
      :reported_min_kelvin,
      :reported_max_kelvin,
      :actual_min_kelvin,
      :actual_max_kelvin,
      :supports_color,
      :supports_temp,
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
