defmodule Hueworks.Import.HomeAssistant do
  @moduledoc """
  Import helpers for Home Assistant exports.
  """

  require Logger

  alias Hueworks.Import.Persist

  def import(export) do
    %{bridge: bridge_attrs, lights: lights} = normalize(export)
    bridge = Persist.get_bridge!(:ha, bridge_attrs.host)
    indexes = Persist.light_indexes()

    log_match_summary(lights, indexes)

    Enum.each(lights, fn light_attrs ->
      parent_id = match_parent(light_attrs, indexes)

      attrs =
        light_attrs
        |> Map.put(:bridge_id, bridge.id)
        |> Map.put(:parent_id, parent_id)

      Persist.upsert_light(attrs)
    end)

    %{bridge: bridge_attrs, lights: lights}
  end

  def normalize(export) do
    host = export["host"] || export[:host]
    light_entities = export["light_entities"] || export[:light_entities] || []

    %{
      bridge: %{
        type: :ha,
        name: "Home Assistant",
        host: host
      },
      lights: Enum.map(light_entities, &normalize_light/1)
    }
  end

  defp normalize_light(light) do
    device = get_value(light, "device") || %{}
    connections = get_value(device, "connections") || []
    identifiers = get_value(device, "identifiers") || []
    macs = macs_from_connections(connections)

    %{
      name: get_value(light, "name") || get_value(light, "entity_id"),
      source: :ha,
      source_id: get_value(light, "entity_id"),
      enabled: true,
      metadata: %{
        "unique_id" => get_value(light, "unique_id"),
        "platform" => get_value(light, "platform"),
        "source" => get_value(light, "source"),
        "device_id" => get_value(light, "device_id"),
        "zone_id" => get_value(light, "zone_id"),
        "device" => %{
          "id" => get_value(device, "id"),
          "name" => get_value(device, "name"),
          "manufacturer" => get_value(device, "manufacturer"),
          "model" => get_value(device, "model"),
          "identifiers" => identifiers,
          "connections" => connections,
          "via_device_id" => get_value(device, "via_device_id")
        },
        "macs" => macs,
        "lutron_serial" => lutron_serial_from_identifiers(identifiers)
      }
    }
  end

  defp match_parent(light_attrs, indexes) do
    metadata = light_attrs.metadata
    hue_mac = match_first(metadata["macs"])
    lutron_serial = metadata["lutron_serial"]
    zone_id = metadata["zone_id"]

    cond do
      zone_id && indexes.caseta_by_zone_id[to_string(zone_id)] ->
        indexes.caseta_by_zone_id[to_string(zone_id)].id

      hue_mac && indexes.hue_by_mac[hue_mac] ->
        indexes.hue_by_mac[hue_mac].id

      lutron_serial && indexes.caseta_by_serial[to_string(lutron_serial)] ->
        indexes.caseta_by_serial[to_string(lutron_serial)].id

      true ->
        nil
    end
  end

  defp log_match_summary(lights, indexes) do
    totals =
      Enum.reduce(lights, %{zone: 0, hue: 0, serial: 0, none: 0}, fn light, acc ->
        metadata = light.metadata
        hue_mac = match_first(metadata["macs"])
        lutron_serial = metadata["lutron_serial"]
        zone_id = metadata["zone_id"]

        cond do
          zone_id && indexes.caseta_by_zone_id[to_string(zone_id)] ->
            %{acc | zone: acc.zone + 1}

          hue_mac && indexes.hue_by_mac[hue_mac] ->
            %{acc | hue: acc.hue + 1}

          lutron_serial && indexes.caseta_by_serial[to_string(lutron_serial)] ->
            %{acc | serial: acc.serial + 1}

          true ->
            %{acc | none: acc.none + 1}
        end
      end)

    Logger.info(
      "HA dedupe matches: zone_id=#{totals.zone}, hue_mac=#{totals.hue}, " <>
        "lutron_serial=#{totals.serial}, unmatched=#{totals.none}"
    )
  end

  defp macs_from_connections(connections) when is_list(connections) do
    connections
    |> Enum.map(fn
      ["mac", value] -> value
      ["MAC", value] -> value
      {"mac", value} -> value
      {"MAC", value} -> value
      _ -> nil
    end)
    |> Enum.filter(&is_binary/1)
  end

  defp macs_from_connections(_connections), do: []

  defp lutron_serial_from_identifiers(identifiers) when is_list(identifiers) do
    identifiers
    |> Enum.find_value(fn
      ["lutron_caseta", value] -> value
      {"lutron_caseta", value} -> value
      _ -> nil
    end)
  end

  defp lutron_serial_from_identifiers(_identifiers), do: nil

  defp match_first([first | _rest]), do: first
  defp match_first(_list), do: nil

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp get_value(_map, _key), do: nil
end
