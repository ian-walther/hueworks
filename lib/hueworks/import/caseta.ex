defmodule Hueworks.Import.Caseta do
  @moduledoc """
  Import helpers for Lutron Caseta exports.
  """

  alias Hueworks.Import.Persist

  def import(export) do
    %{bridge: bridge_attrs, lights: lights, groups: groups} = normalize(export)
    bridge = Persist.get_bridge!(:caseta, bridge_attrs.host)

    Enum.each(groups, fn group_attrs ->
      attrs = Map.merge(group_attrs, %{bridge_id: bridge.id})
      Persist.upsert_group(attrs)
    end)

    Enum.each(lights, fn light_attrs ->
      attrs = Map.merge(light_attrs, %{bridge_id: bridge.id})
      Persist.upsert_light(attrs)
    end)

    %{bridge: bridge_attrs, lights: lights, groups: groups}
  end

  def normalize(export) do
    bridge_host = export["bridge_ip"] || export[:bridge_ip]

    lights =
      export
      |> get_in(["lights"]) ||
        export[:lights] ||
        []

    groups =
      export
      |> get_in(["groups"]) ||
        export[:groups] ||
        []

    %{
      bridge: %{
        type: :caseta,
        name: "Caseta Bridge",
        host: bridge_host
      },
      lights: normalize_lights(lights),
      groups: normalize_groups(groups)
    }
  end

  defp normalize_lights(lights) when is_list(lights) do
    Enum.map(lights, fn light ->
      %{
        name: get_value(light, "name"),
        source: :caseta,
        source_id: to_string(get_value(light, "zone_id")),
        enabled: true,
        reported_min_kelvin: nil,
        reported_max_kelvin: nil,
        actual_min_kelvin: nil,
        actual_max_kelvin: nil,
        supports_temp: false,
        supports_color: false,
        metadata: %{
          "device_id" => get_value(light, "device_id"),
          "area_id" => get_value(light, "area_id"),
          "type" => get_value(light, "type"),
          "model" => get_value(light, "model"),
          "serial" => get_value(light, "serial")
        }
      }
    end)
  end

  defp normalize_lights(_lights), do: []

  defp normalize_groups(groups) when is_list(groups) do
    Enum.map(groups, fn group ->
      %{
        name: get_value(group, "name"),
        source: :caseta,
        source_id: to_string(get_value(group, "group_id")),
        enabled: true,
        reported_min_kelvin: nil,
        reported_max_kelvin: nil,
        actual_min_kelvin: nil,
        actual_max_kelvin: nil,
        supports_temp: false,
        supports_color: false,
        metadata: %{
          "type" => get_value(group, "type")
        }
      }
    end)
  end

  defp normalize_groups(_groups), do: []

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp get_value(_map, _key), do: nil
end
