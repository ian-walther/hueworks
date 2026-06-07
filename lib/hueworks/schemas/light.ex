defmodule Hueworks.Schemas.Light do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lights" do
    field(:name, :string)
    field(:display_name, :string)
    field(:source, Ecto.Enum, values: [:hue, :caseta, :ha, :z2m])
    field(:source_id, :string)
    belongs_to(:bridge, Hueworks.Schemas.Bridge)
    belongs_to(:room, Hueworks.Schemas.Room)
    belongs_to(:canonical_light, __MODULE__)
    has_many(:scene_component_lights, Hueworks.Schemas.SceneComponentLight)
    has_many(:scene_components, through: [:scene_component_lights, :scene_component])
    field(:reported_min_kelvin, :integer)
    field(:reported_max_kelvin, :integer)
    field(:actual_min_kelvin, :integer)
    field(:actual_max_kelvin, :integer)
    field(:extended_min_kelvin, :integer)
    field(:extended_kelvin_range, :boolean, default: false)
    field(:supports_color, :boolean, default: false)
    field(:supports_temp, :boolean, default: false)
    field(:enabled, :boolean, default: true)
    field(:ha_export_mode, Ecto.Enum, values: [:none, :switch, :light], default: :none)
    field(:homekit_export_mode, Ecto.Enum, values: [:none, :switch], default: :none)
    field(:metadata, :map, default: %{})
    field(:external_id, :string)
    field(:normalized_json, :map, default: %{})

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
      :room_id,
      :canonical_light_id,
      :reported_min_kelvin,
      :reported_max_kelvin,
      :actual_min_kelvin,
      :actual_max_kelvin,
      :extended_min_kelvin,
      :extended_kelvin_range,
      :supports_color,
      :supports_temp,
      :enabled,
      :ha_export_mode,
      :homekit_export_mode,
      :metadata,
      :external_id,
      :normalized_json
    ])
    |> validate_required([:name, :source, :source_id, :bridge_id])
    |> validate_change(:canonical_light_id, fn :canonical_light_id, canonical_light_id ->
      if light.id && canonical_light_id == light.id do
        [canonical_light_id: "cannot reference itself"]
      else
        []
      end
    end)
    |> validate_actual_kelvin_source()
    |> unique_constraint([:bridge_id, :source_id])
  end

  defp validate_actual_kelvin_source(changeset) do
    source = get_field(changeset, :source)
    actual_min = get_field(changeset, :actual_min_kelvin)
    actual_max = get_field(changeset, :actual_max_kelvin)
    extended_min = get_field(changeset, :extended_min_kelvin)

    if source && source not in [:ha, :z2m] &&
         (not is_nil(actual_min) or not is_nil(actual_max) or not is_nil(extended_min)) do
      changeset
      |> add_error(:actual_min_kelvin, "only supported for HA and Z2M entities")
      |> add_error(:actual_max_kelvin, "only supported for HA and Z2M entities")
      |> add_error(:extended_min_kelvin, "only supported for HA and Z2M entities")
    else
      changeset
    end
  end
end
