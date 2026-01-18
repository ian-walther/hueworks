defmodule Hueworks.Import.Hue do
  @moduledoc """
  Import helpers for Hue exports.
  """

  alias Hueworks.Import.Persist

  def import(export) do
    %{bridges: bridges, lights: lights, groups: groups} = normalize(export)

    Enum.each(bridges, fn %{lights: bridge_lights, groups: bridge_groups} = bridge_payload ->
      bridge = Persist.get_bridge!(:hue, bridge_payload.bridge.host)

      Enum.each(bridge_lights, fn light_attrs ->
        attrs = Map.merge(light_attrs, %{bridge_id: bridge.id})
        Persist.upsert_light(attrs)
      end)

      Enum.each(bridge_groups, fn group_attrs ->
        attrs = Map.merge(group_attrs, %{bridge_id: bridge.id})
        Persist.upsert_group(attrs)
      end)

      attach_group_memberships(bridge)
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
        groups = normalize_groups(bridge["groups"] || bridge[:groups] || %{}, host, lights)

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
      capabilities = get_value(light, "capabilities")
      {min_kelvin, max_kelvin} = temp_range_from_capabilities(capabilities)
      {supports_temp, supports_color} = supports_from_capabilities(capabilities)

      %{
        name: get_value(light, "name"),
        source: :hue,
        source_id: to_string(source_id),
        enabled: true,
        min_kelvin: min_kelvin,
        max_kelvin: max_kelvin,
        supports_temp: supports_temp,
        supports_color: supports_color,
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

  defp temp_range_from_capabilities(capabilities) when is_map(capabilities) do
    control = get_value(capabilities, "control") || %{}
    ct = get_value(control, "ct") || %{}
    min_mired = to_number(get_value(ct, "min"))
    max_mired = to_number(get_value(ct, "max"))

    if is_number(min_mired) and is_number(max_mired) and min_mired > 0 and max_mired > 0 do
      min_kelvin = round(1_000_000 / max_mired)
      max_kelvin = round(1_000_000 / min_mired)
      {min_kelvin, max_kelvin}
    else
      {nil, nil}
    end
  end

  defp temp_range_from_capabilities(_capabilities), do: {nil, nil}

  defp supports_from_capabilities(capabilities) when is_map(capabilities) do
    control = get_value(capabilities, "control") || %{}
    ct = get_value(control, "ct") || %{}
    min_mired = to_number(get_value(ct, "min"))
    max_mired = to_number(get_value(ct, "max"))

    supports_temp =
      get_value(capabilities, "color_temp") == true or
        (is_number(min_mired) and is_number(max_mired) and min_mired > 0 and max_mired > 0)

    supports_color =
      get_value(capabilities, "color") == true or
        not is_nil(get_value(control, "colorgamut"))

    {supports_temp, supports_color}
  end

  defp supports_from_capabilities(_capabilities), do: {false, false}

  defp to_number(value) when is_integer(value), do: value
  defp to_number(value) when is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp to_number(_value), do: nil

  defp supports_from_members(members, supports_by_source_id) when is_list(members) do
    Enum.reduce(members, {false, false}, fn member_id, {temp_acc, color_acc} ->
      case Map.get(supports_by_source_id, to_string(member_id)) do
        {supports_temp, supports_color} ->
          {temp_acc or supports_temp, color_acc or supports_color}

        _ ->
          {temp_acc, color_acc}
      end
    end)
  end

  defp supports_from_members(_members, _supports_by_source_id), do: {false, false}

  defp normalize_groups(groups, bridge_host, lights) when is_map(groups) do
    supports_by_source_id =
      Enum.reduce(lights, %{}, fn light, acc ->
        Map.put(acc, light.source_id, {light.supports_temp, light.supports_color})
      end)

    groups
    |> Enum.map(fn {id, group} ->
      source_id = get_value(group, "id") || id
      members = get_value(group, "lights") || []
      {supports_temp, supports_color} = supports_from_members(members, supports_by_source_id)

      %{
        name: get_value(group, "name"),
        source: :hue,
        source_id: to_string(source_id),
        enabled: true,
        supports_temp: supports_temp,
        supports_color: supports_color,
        metadata: %{
          "bridge_host" => bridge_host,
          "type" => get_value(group, "type"),
          "lights" => members
        }
      }
    end)
  end

  defp normalize_groups(_groups, _bridge_host, _lights), do: []

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp get_value(_map, _key), do: nil

  defp attach_group_memberships(bridge) do
    groups_by_id = Persist.groups_by_source_id(bridge.id, :hue)
    lights_by_id = Persist.lights_by_source_id(bridge.id, :hue)

    Enum.each(groups_by_id, fn {_source_id, group} ->
      members = group.metadata["lights"] || []

      Enum.each(members, fn light_id ->
        case Map.get(lights_by_id, to_string(light_id)) do
          nil -> :ok
          light -> Persist.upsert_group_light(group.id, light.id)
        end
      end)
    end)
  end
end
