defmodule Hueworks.Import.EntityAttrs do
  @moduledoc false

  alias Hueworks.Import.{Identifiers, Normalize, NormalizeJson, Source}

  def light_attrs(bridge, light) do
    capabilities = Normalize.fetch(light, :capabilities) || %{}

    %{
      name: Normalize.fetch(light, :name) || "Light",
      source: Source.normalize(Normalize.fetch(light, :source)),
      source_id: source_id(light),
      bridge_id: bridge.id,
      supports_color: capabilities |> Normalize.fetch(:color) |> Normalize.truthy?(),
      supports_temp: capabilities |> Normalize.fetch(:color_temp) |> Normalize.truthy?(),
      reported_min_kelvin: Normalize.fetch(capabilities, :reported_kelvin_min),
      reported_max_kelvin: Normalize.fetch(capabilities, :reported_kelvin_max),
      metadata: light_metadata(light),
      external_id: Identifiers.light_external_id(light),
      normalized_json: NormalizeJson.to_map(light)
    }
  end

  def group_attrs(bridge, group) do
    capabilities = Normalize.fetch(group, :capabilities) || %{}

    %{
      name: Normalize.fetch(group, :name) || "Group",
      source: Source.normalize(Normalize.fetch(group, :source)),
      source_id: source_id(group),
      bridge_id: bridge.id,
      supports_color: capabilities |> Normalize.fetch(:color) |> Normalize.truthy?(),
      supports_temp: capabilities |> Normalize.fetch(:color_temp) |> Normalize.truthy?(),
      reported_min_kelvin: Normalize.fetch(capabilities, :reported_kelvin_min),
      reported_max_kelvin: Normalize.fetch(capabilities, :reported_kelvin_max),
      metadata: group_metadata(group),
      external_id: Identifiers.group_external_id(group),
      normalized_json: NormalizeJson.to_map(group)
    }
  end

  def hidden_duplicate_overlay(attrs, canonical_id, :light) do
    Map.merge(attrs, %{
      area_id: nil,
      enabled: false,
      ha_export_mode: :none,
      homekit_export_mode: :none,
      canonical_light_id: canonical_id
    })
  end

  def hidden_duplicate_overlay(attrs, canonical_id, :group) do
    Map.merge(attrs, %{
      area_id: nil,
      enabled: false,
      ha_export_mode: :none,
      homekit_export_mode: :none,
      canonical_group_id: canonical_id
    })
  end

  def source_id(entity),
    do: entity |> Normalize.fetch(:source_id) |> Normalize.normalize_source_id()

  defp light_metadata(light) do
    base = Normalize.fetch(light, :metadata) || %{}
    identifiers = Normalize.fetch(light, :identifiers) || %{}

    base
    |> Map.put("identifiers", identifiers)
  end

  defp group_metadata(group), do: Normalize.fetch(group, :metadata) || %{}
end
