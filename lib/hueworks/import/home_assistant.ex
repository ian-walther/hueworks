defmodule Hueworks.Import.HomeAssistant do
  @moduledoc """
  Import helpers for Home Assistant exports.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Hueworks.Import.Persist
  alias Hueworks.Repo
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Schemas.Light

  def import(export) do
    %{bridge: bridge_attrs, lights: lights, groups: groups} = normalize(export)
    bridge = Persist.get_bridge!(:ha, bridge_attrs.host)
    indexes = Persist.light_indexes()

    log_match_summary(lights, indexes)

    Enum.each(groups, fn group_attrs ->
      attrs = Map.merge(group_attrs, %{bridge_id: bridge.id})
      Persist.upsert_group(attrs)
    end)

    Enum.each(lights, fn light_attrs ->
      canonical_light_id = match_parent(light_attrs, indexes)

      attrs =
        light_attrs
        |> Map.put(:bridge_id, bridge.id)
        |> Map.put(:canonical_light_id, canonical_light_id)

      Persist.upsert_light(attrs)
    end)

    attach_group_memberships(bridge, groups)
    link_canonical_groups(bridge)

    %{bridge: bridge_attrs, lights: lights, groups: groups}
  end

  def normalize(export) do
    host = export["host"] || export[:host]
    light_entities = export["light_entities"] || export[:light_entities] || []
    group_entities = export["group_entities"] || export[:group_entities] || []

    %{
      bridge: %{
        type: :ha,
        name: "Home Assistant",
        host: host
      },
      lights: light_entities |> Enum.reject(&group_light?/1) |> Enum.map(&normalize_light/1),
      groups:
        (group_entities ++ group_lights_as_groups(light_entities))
        |> normalize_groups(light_entities)
    }
  end

  defp normalize_light(light) do
    device = get_value(light, "device") || %{}
    connections = get_value(device, "connections") || []
    identifiers = get_value(device, "identifiers") || []
    macs = macs_from_connections(connections)
    {min_kelvin, max_kelvin} = temp_range_from_ha(light)
    {supports_temp, supports_color} = supports_from_ha(light)

    %{
      name: get_value(light, "name") || get_value(light, "entity_id"),
      source: :ha,
      source_id: get_value(light, "entity_id"),
      enabled: true,
      reported_min_kelvin: min_kelvin,
      reported_max_kelvin: max_kelvin,
      actual_min_kelvin: nil,
      actual_max_kelvin: nil,
      supports_temp: supports_temp,
      supports_color: supports_color,
      metadata: %{
        "unique_id" => get_value(light, "unique_id"),
        "platform" => get_value(light, "platform"),
        "source" => get_value(light, "source"),
        "device_id" => get_value(light, "device_id"),
        "zone_id" => get_value(light, "zone_id"),
        "temp_range" => get_value(light, "temp_range"),
        "supported_color_modes" => get_value(light, "supported_color_modes"),
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

  defp normalize_group(group, supports_by_entity_id) do
    members = get_value(group, "members") || []
    {supports_temp, supports_color} = supports_from_members(members, supports_by_entity_id)
    {reported_min_kelvin, reported_max_kelvin} =
      reported_range_from_members(members, supports_by_entity_id)

    %{
      name: get_value(group, "name") || get_value(group, "entity_id"),
      source: :ha,
      source_id: get_value(group, "entity_id"),
      enabled: true,
      supports_temp: supports_temp,
      supports_color: supports_color,
      reported_min_kelvin: reported_min_kelvin,
      reported_max_kelvin: reported_max_kelvin,
      actual_min_kelvin: nil,
      actual_max_kelvin: nil,
      metadata: %{
        "platform" => get_value(group, "platform"),
        "members" => members
      }
    }
  end

  defp normalize_groups(groups, light_entities) do
    supports_by_entity_id =
      light_entities
      |> Enum.reject(&group_light?/1)
      |> Enum.map(&normalize_light/1)
      |> Enum.reduce(%{}, fn light, acc ->
        Map.put(
          acc,
          light.source_id,
          {light.supports_temp, light.supports_color, light.reported_min_kelvin,
           light.reported_max_kelvin}
        )
      end)

    Enum.map(groups, &normalize_group(&1, supports_by_entity_id))
  end

  defp group_light?(light) do
    platform = get_value(light, "platform")
    macs = get_value(light, "device") |> get_value("connections") |> macs_from_connections()

    platform in ["group", "light_group"] or (platform == "hue" and macs == [])
  end

  defp group_lights_as_groups(light_entities) do
    Enum.filter(light_entities, &group_light?/1)
  end

  defp temp_range_from_ha(light) do
    range = get_value(light, "temp_range") || %{}
    min_kelvin = get_value(range, "min_kelvin")
    max_kelvin = get_value(range, "max_kelvin")
    min_mireds = get_value(range, "min_mireds")
    max_mireds = get_value(range, "max_mireds")

    cond do
      is_number(min_kelvin) and is_number(max_kelvin) ->
        {round(min_kelvin), round(max_kelvin)}

      is_number(min_mireds) and is_number(max_mireds) ->
        min_k = round(1_000_000 / max_mireds)
        max_k = round(1_000_000 / min_mireds)
        {min_k, max_k}

      true ->
        {nil, nil}
    end
  end

  defp supports_from_ha(light) do
    temp_range = get_value(light, "temp_range") || %{}
    modes = get_value(light, "supported_color_modes") || []

    supports_temp =
      is_number(get_value(temp_range, "min_kelvin")) or
        is_number(get_value(temp_range, "min_mireds")) or
        Enum.member?(modes, "color_temp") or Enum.member?(modes, "color_temp_kelvin")

    supports_color =
      Enum.any?(modes, &(&1 in ["hs", "rgb", "rgbw", "rgbww", "xy"]))

    {supports_temp, supports_color}
  end

  defp supports_from_members(members, supports_by_entity_id) when is_list(members) do
    Enum.reduce(members, {false, false}, fn member_id, {temp_acc, color_acc} ->
      case Map.get(supports_by_entity_id, to_string(member_id)) do
        {supports_temp, supports_color, _min_k, _max_k} ->
          {temp_acc or supports_temp, color_acc or supports_color}

        _ ->
          {temp_acc, color_acc}
      end
    end)
  end

  defp supports_from_members(_members, _supports_by_entity_id), do: {false, false}

  defp reported_range_from_members(members, supports_by_entity_id) when is_list(members) do
    {mins, maxes} =
      Enum.reduce(members, {[], []}, fn member_id, {mins, maxes} ->
        case Map.get(supports_by_entity_id, to_string(member_id)) do
          {_supports_temp, _supports_color, min_k, max_k}
          when is_number(min_k) and is_number(max_k) ->
            {[min_k | mins], [max_k | maxes]}

          _ ->
            {mins, maxes}
        end
      end)

    if mins == [] or maxes == [] do
      {nil, nil}
    else
      {Enum.min(mins), Enum.max(maxes)}
    end
  end

  defp reported_range_from_members(_members, _supports_by_entity_id), do: {nil, nil}

  defp get_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp get_value(_map, _key), do: nil

  defp attach_group_memberships(bridge, groups) do
    groups_by_id = Persist.groups_by_source_id(bridge.id, :ha)
    lights_by_id = Persist.lights_by_source_id(bridge.id, :ha)

    Enum.each(groups, fn group ->
      group_id = get_value(group, "source_id")
      members = get_value(group, "metadata") |> get_value("members") || []

      case Map.get(groups_by_id, to_string(group_id)) do
        nil ->
          :ok

        db_group ->
          Enum.each(members, fn entity_id ->
            case Map.get(lights_by_id, to_string(entity_id)) do
              nil -> :ok
              light -> Persist.upsert_group_light(db_group.id, light.id)
            end
          end)
      end
    end)
  end

  defp link_canonical_groups(bridge) do
    canonical_groups =
      Repo.all(
        from(gl in GroupLight,
          join: g in Group,
          on: g.id == gl.group_id,
          where: g.source != :ha,
          select: {g.id, gl.light_id}
        )
      )
      |> Enum.reduce(%{}, fn {group_id, light_id}, acc ->
        Map.update(acc, group_id, MapSet.new([light_id]), &MapSet.put(&1, light_id))
      end)

    canonical_by_members =
      canonical_groups
      |> Enum.reduce(%{}, fn {group_id, members}, acc ->
        key = members |> MapSet.to_list() |> Enum.sort()
        Map.put_new(acc, key, group_id)
      end)

    ha_groups =
      Repo.all(from(g in Group, where: g.bridge_id == ^bridge.id and g.source == :ha))

    ha_group_by_source_id =
      Enum.reduce(ha_groups, %{}, fn group, acc -> Map.put(acc, group.source_id, group) end)

    ha_lights =
      Repo.all(from(l in Light, where: l.bridge_id == ^bridge.id and l.source == :ha))

    ha_light_by_source_id =
      Enum.reduce(ha_lights, %{}, fn light, acc -> Map.put(acc, light.source_id, light) end)

    ha_canonical_by_light =
      Enum.reduce(ha_lights, %{}, fn light, acc -> Map.put(acc, light.id, light.canonical_light_id) end)

    ha_group_members =
      Enum.reduce(ha_groups, %{}, fn group, acc ->
        members = get_value(group.metadata, "members") || []
        light_ids = expand_member_lights(members, ha_group_by_source_id, ha_light_by_source_id, MapSet.new())
        Map.put(acc, group.id, light_ids)
      end)

    {linked, total} =
      Enum.reduce(ha_group_members, {0, 0}, fn {group_id, light_ids}, {linked, total} ->
        total = total + 1

        canonical_ids =
          light_ids
          |> Enum.map(&Map.get(ha_canonical_by_light, &1))

        if Enum.any?(canonical_ids, &is_nil/1) do
          {linked, total}
        else
          key = canonical_ids |> Enum.sort()

          case Map.get(canonical_by_members, key) do
            nil ->
              {linked, total}

            canonical_group_id ->
              Repo.update_all(
                from(g in Group, where: g.id == ^group_id),
                set: [canonical_group_id: canonical_group_id]
              )

              {linked + 1, total}
          end
        end
      end)

    Logger.info("HA group canonical matches: #{linked}/#{total}")
  end

  defp expand_member_lights(members, ha_group_by_source_id, ha_light_by_source_id, visited)
       when is_list(members) do
    Enum.reduce(members, [], fn member_id, acc ->
      cond do
        light = Map.get(ha_light_by_source_id, to_string(member_id)) ->
          [light.id | acc]

        group = Map.get(ha_group_by_source_id, to_string(member_id)) ->
          if MapSet.member?(visited, group.id) do
            acc
          else
            nested_members = get_value(group.metadata, "members") || []

            nested =
              expand_member_lights(
                nested_members,
                ha_group_by_source_id,
                ha_light_by_source_id,
                MapSet.put(visited, group.id)
              )

            nested ++ acc
          end

        true ->
          acc
      end
    end)
    |> Enum.uniq()
  end

  defp expand_member_lights(_members, _ha_group_by_source_id, _ha_light_by_source_id, _visited), do: []
end
