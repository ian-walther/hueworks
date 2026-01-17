defmodule Hueworks.Import.Hue do
  @moduledoc """
  Import helpers for Hue exports.
  """

  alias Hueworks.Import.Persist

  def import(export) do
    %{bridges: bridges, lights: lights, groups: groups} = normalize(export)

    Enum.each(bridges, fn %{lights: bridge_lights} = bridge_payload ->
      bridge = Persist.get_bridge!(:hue, bridge_payload.bridge.host)

      Enum.each(bridge_payload.groups, fn group_attrs ->
        attrs = Map.merge(group_attrs, %{bridge_id: bridge.id})
        Persist.upsert_group(attrs)
      end)

      Enum.each(bridge_lights, fn light_attrs ->
        attrs = Map.merge(light_attrs, %{bridge_id: bridge.id})
        Persist.upsert_light(attrs)
      end)
    end)

    %{bridges: bridges, lights: lights, groups: groups}
  end

  def normalize(export) do
    bridges = export["bridges"] || export[:bridges] || []

    normalized =
      Enum.map(bridges, fn bridge ->
        host = bridge["host"] || bridge[:host]
        name = bridge["name"] || bridge[:name] || host
        lights = normalize_lights(bridge["lights"] || bridge[:lights] || %{}, host)
        groups = normalize_groups(bridge["groups"] || bridge[:groups] || %{}, host)

        %{
          bridge: %{
            type: :hue,
            name: name,
            host: host
          },
          lights: lights,
          groups: groups
        }
      end)

    %{
      bridges: normalized,
      lights: Enum.flat_map(normalized, & &1.lights),
      groups: Enum.flat_map(normalized, & &1.groups)
    }
  end

  defp normalize_lights(lights, bridge_host) when is_map(lights) do
    lights
    |> Enum.map(fn {id, light} ->
      source_id = get_value(light, "id") || id

      %{
        name: get_value(light, "name"),
        source: :hue,
        source_id: to_string(source_id),
        enabled: true,
        metadata: %{
          "bridge_host" => bridge_host,
          "uniqueid" => get_value(light, "uniqueid"),
          "mac" => get_value(light, "mac"),
          "modelid" => get_value(light, "modelid"),
          "productname" => get_value(light, "productname"),
          "type" => get_value(light, "type"),
          "capabilities" => get_value(light, "capabilities")
        }
      }
    end)
  end

  defp normalize_lights(_lights, _bridge_host), do: []

  defp normalize_groups(groups, bridge_host) when is_map(groups) do
    groups
    |> Enum.map(fn {id, group} ->
      source_id = get_value(group, "id") || id

      %{
        name: get_value(group, "name"),
        source: :hue,
        source_id: to_string(source_id),
        enabled: true,
        metadata: %{
          "bridge_host" => bridge_host,
          "type" => get_value(group, "type"),
          "lights" => get_value(group, "lights") || []
        }
      }
    end)
  end

  defp normalize_groups(_groups, _bridge_host), do: []

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp get_value(_map, _key), do: nil
end
