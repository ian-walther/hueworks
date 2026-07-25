defmodule Hueworks.HomeAssistant.Inventory do
  @moduledoc """
  A read-only projection of Home Assistant setup evidence.

  Inventory is intentionally separate from import materialization. It can guide native bridge
  setup and identify HA-only entities without making Home Assistant the owner of HueWorks state.
  """

  alias Hueworks.Bridges
  alias Hueworks.Import.Normalize
  alias Hueworks.Schemas.{Bridge, BridgeImport}

  @native_domains %{
    "hue" => :hue,
    "lutron_caseta" => :caseta,
    "mqtt" => :z2m
  }

  def latest(%Bridge{type: :ha} = bridge) do
    case Bridges.latest_import(bridge) do
      %BridgeImport{} = bridge_import -> {:ok, from_import(bridge_import)}
      nil -> {:error, :inventory_not_fetched}
    end
  end

  def from_import(%BridgeImport{} = bridge_import) do
    from_snapshot(bridge_import.raw_blob || %{}, bridge_import.normalized_blob || %{})
  end

  def from_snapshot(raw, normalized) when is_map(raw) and is_map(normalized) do
    lights = Normalize.fetch(normalized, :lights) || []
    groups = Normalize.fetch(normalized, :groups) || []
    config_entries = Normalize.fetch(raw, :config_entries) |> Normalize.normalize_list()
    device_registry = Normalize.fetch(raw, :device_registry) |> Normalize.normalize_list()

    native_sources = native_sources(config_entries, device_registry, lights, groups)

    %{
      floors: spaces_of_kind(normalized, "ha_floor"),
      areas: spaces_of_kind(normalized, "ha_area"),
      lights: lights,
      groups: groups,
      config_entries: config_entries,
      native_sources: native_sources,
      native_wrappers: Enum.filter(lights, &(entity_source(&1) in [:hue, :caseta, :z2m])),
      ha_only_entities: Enum.reject(lights, &(entity_source(&1) in [:hue, :caseta, :z2m])),
      warnings: inventory_warnings(raw, normalized)
    }
  end

  def entity_source(entity) do
    metadata = Normalize.fetch(entity, :metadata) || %{}
    platform = Normalize.fetch(metadata, :platform)
    reported_source = Normalize.fetch(metadata, :source)

    cond do
      platform == "hue" or reported_source == "hue" -> :hue
      platform == "lutron_caseta" or reported_source == "lutron" -> :caseta
      platform == "mqtt" -> :z2m
      true -> :ha_only
    end
  end

  defp native_sources(config_entries, device_registry, lights, groups) do
    entities = lights ++ groups

    config_entries
    |> Enum.flat_map(fn entry ->
      domain = Normalize.fetch(entry, :domain)

      case Map.get(@native_domains, domain) do
        nil ->
          []

        kind ->
          entry_id =
            Normalize.fetch(entry, :entry_id) || Normalize.fetch(entry, :config_entry_id)

          entity_count =
            Enum.count(entities, fn entity ->
              metadata = Normalize.fetch(entity, :metadata) || %{}
              Normalize.fetch(metadata, :config_entry_id) == entry_id
            end)

          [
            %{
              kind: kind,
              domain: domain,
              config_entry_id: entry_id,
              title: Normalize.fetch(entry, :title) || domain,
              entity_count: entity_count,
              confidence: native_source_confidence(kind, entry),
              external_id: native_source_external_id(kind, entry, device_registry),
              host: native_source_host(kind, entry)
            }
          ]
      end
    end)
    |> Enum.uniq_by(&{&1.kind, &1.config_entry_id})
  end

  defp native_source_confidence(:z2m, _entry), do: :possible
  defp native_source_confidence(_kind, _entry), do: :confirmed

  defp native_source_external_id(:hue, entry, devices) do
    entry_id = Normalize.fetch(entry, :entry_id) || Normalize.fetch(entry, :config_entry_id)

    devices
    |> Enum.filter(&device_for_entry?(&1, entry_id))
    |> Enum.flat_map(&(Normalize.fetch(&1, :identifiers) |> Normalize.normalize_list()))
    |> Enum.find_value(fn
      ["hue", id] when is_binary(id) -> hue_bridge_id(id)
      {"hue", id} when is_binary(id) -> hue_bridge_id(id)
      _ -> nil
    end)
  end

  defp native_source_external_id(:caseta, entry, _devices) do
    entry
    |> Normalize.fetch(:title)
    |> case do
      value when is_binary(value) ->
        value = value |> String.trim() |> String.downcase()
        if Regex.match?(~r/^[0-9a-f]{8}$/, value), do: value

      _ ->
        nil
    end
  end

  defp native_source_external_id(_kind, _entry, _devices), do: nil

  defp native_source_host(:z2m, entry) do
    entry
    |> Normalize.fetch(:title)
    |> network_host()
  end

  defp native_source_host(_kind, _entry), do: nil

  defp device_for_entry?(device, entry_id) when is_binary(entry_id) do
    config_entries =
      device
      |> Normalize.fetch(:config_entries)
      |> Normalize.normalize_list()

    entry_id in config_entries or Normalize.fetch(device, :config_entry_id) == entry_id
  end

  defp device_for_entry?(_device, _entry_id), do: false

  defp hue_bridge_id(id) do
    normalized = id |> String.trim() |> String.downcase()
    if Regex.match?(~r/^[0-9a-f]{16}$/, normalized), do: normalized
  end

  defp network_host(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        nil

      match?({:ok, _address}, :inet.parse_address(String.to_charlist(value))) ->
        value

      String.contains?(value, ".") and
          Regex.match?(~r/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/i, value) ->
        value

      true ->
        nil
    end
  end

  defp network_host(_value), do: nil

  defp spaces_of_kind(normalized, kind) do
    normalized
    |> Normalize.external_spaces()
    |> Enum.filter(&(Normalize.fetch(&1, :kind) == kind))
  end

  defp inventory_warnings(raw, normalized) do
    []
    |> maybe_warn(Normalize.fetch(raw, :floors) == nil, :floor_registry_unavailable)
    |> maybe_warn(Normalize.fetch(raw, :config_entries) == nil, :config_entries_unavailable)
    |> maybe_warn(Normalize.external_spaces(normalized) == [], :no_spatial_inventory)
  end

  defp maybe_warn(warnings, true, warning), do: warnings ++ [warning]
  defp maybe_warn(warnings, false, _warning), do: warnings
end
