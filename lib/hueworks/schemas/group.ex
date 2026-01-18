defmodule Hueworks.Schemas.Group do
  use Ecto.Schema
  import Ecto.Changeset

  schema "groups" do
    field(:name, :string)
    field(:display_name, :string)
    field(:source, Ecto.Enum, values: [:hue, :caseta, :ha])
    field(:source_id, :string)
    belongs_to(:bridge, Hueworks.Schemas.Bridge)
    belongs_to(:parent_group, __MODULE__)
    belongs_to(:canonical_group, __MODULE__)
    field(:supports_color, :boolean, default: false)
    field(:supports_temp, :boolean, default: false)
    field(:reported_min_kelvin, :integer)
    field(:reported_max_kelvin, :integer)
    field(:actual_min_kelvin, :integer)
    field(:actual_max_kelvin, :integer)
    field(:enabled, :boolean, default: true)
    field(:metadata, :map, default: %{})
    has_many(:group_lights, Hueworks.Schemas.GroupLight)
    has_many(:lights, through: [:group_lights, :light])

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [
      :name,
      :display_name,
      :source,
      :source_id,
      :bridge_id,
      :parent_group_id,
      :canonical_group_id,
      :supports_color,
      :supports_temp,
      :reported_min_kelvin,
      :reported_max_kelvin,
      :actual_min_kelvin,
      :actual_max_kelvin,
      :enabled,
      :metadata
    ])
    |> validate_required([:name, :source, :source_id, :bridge_id])
    |> validate_change(:parent_group_id, fn :parent_group_id, parent_group_id ->
      if group.id && parent_group_id == group.id do
        [parent_group_id: "cannot reference itself"]
      else
        []
      end
    end)
    |> validate_change(:canonical_group_id, fn :canonical_group_id, canonical_group_id ->
      if group.id && canonical_group_id == group.id do
        [canonical_group_id: "cannot reference itself"]
      else
        []
      end
    end)
    |> unique_constraint([:bridge_id, :source_id])
  end
end
