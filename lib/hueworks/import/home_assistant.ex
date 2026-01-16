defmodule Hueworks.Import.HomeAssistant do
  @moduledoc """
  Import helpers for Home Assistant exports.
  """

  alias Hueworks.Import.Persist

  def import(export) do
    %{bridge: bridge_attrs, lights: lights} = normalize(export)
    bridge = Persist.upsert_bridge(bridge_attrs)
    indexes = Persist.light_indexes()

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
        host: host,
        credentials: %{}
      },
      lights: Enum.map(light_entities, &normalize_light/1)
    }
  end

  defp normalize_light(light) do
    device = light["device"] || %{}
    connections = device["connections"] || []
    identifiers = device["identifiers"] || []
    macs = macs_from_connections(connections)

    %{
      name: light["name"] || light["entity_id"],
      source: :ha,
      source_id: light["entity_id"],
      enabled: true,
      metadata: %{
        "unique_id" => light["unique_id"],
        "platform" => light["platform"],
        "source" => light["source"],
        "device_id" => light["device_id"],
        "device" => %{
          "id" => device["id"],
          "name" => device["name"],
          "manufacturer" => device["manufacturer"],
          "model" => device["model"],
          "identifiers" => identifiers,
          "connections" => connections,
          "via_device_id" => device["via_device_id"]
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

    cond do
      hue_mac && indexes.hue_by_mac[hue_mac] ->
        indexes.hue_by_mac[hue_mac].id

      lutron_serial && indexes.caseta_by_serial[to_string(lutron_serial)] ->
        indexes.caseta_by_serial[to_string(lutron_serial)].id

      true ->
        nil
    end
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
end
