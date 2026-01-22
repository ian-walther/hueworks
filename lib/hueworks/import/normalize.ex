defmodule Hueworks.Import.Normalize do
  @moduledoc false

  alias Hueworks.Schemas.Bridge

  @schema_version 1

  def normalize(%Bridge{} = bridge, raw_blob) do
    normalize(bridge, raw_blob, %{})
  end

  def normalize(%Bridge{} = bridge, raw_blob, opts) when is_map(opts) do
    case bridge.type do
      :hue -> Hueworks.Import.Normalize.Hue.normalize(bridge, raw_blob, opts)
      :ha -> Hueworks.Import.Normalize.HomeAssistant.normalize(bridge, raw_blob, opts)
      :caseta -> Hueworks.Import.Normalize.Caseta.normalize(bridge, raw_blob, opts)
    end
  end
  def base_normalized(bridge, rooms, groups, lights, memberships) do
    %{
      schema_version: @schema_version,
      bridge: %{
        id: bridge.id,
        type: bridge.type,
        name: bridge.name,
        host: bridge.host
      },
      normalized_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      rooms: rooms,
      groups: groups,
      lights: lights,
      memberships: memberships
    }
  end

  def aggregate_capabilities(member_ids, light_capabilities_by_id) do
    capabilities =
      Enum.reduce(member_ids, %{}, fn id, acc ->
        case Map.get(light_capabilities_by_id, id) do
          nil -> acc
          caps -> Map.update(acc, :members, [caps], fn list -> [caps | list] end)
        end
      end)

    members = Map.get(capabilities, :members, [])

    %{
      brightness: Enum.any?(members, & &1.brightness),
      color: Enum.any?(members, & &1.color),
      color_temp: Enum.any?(members, & &1.color_temp),
      reported_kelvin_min: min_reported_kelvin(members),
      reported_kelvin_max: max_reported_kelvin(members)
    }
  end

  def min_reported_kelvin([]), do: nil

  def min_reported_kelvin(members) do
    members
    |> Enum.map(& &1.reported_kelvin_min)
    |> Enum.filter(&is_number/1)
    |> Enum.min(fn -> nil end)
  end

  def max_reported_kelvin([]), do: nil

  def max_reported_kelvin(members) do
    members
    |> Enum.map(& &1.reported_kelvin_max)
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> nil end)
  end

  def normalize_group_type("Room"), do: "room"
  def normalize_group_type("Zone"), do: "zone"
  def normalize_group_type("LightGroup"), do: "group"
  def normalize_group_type(_type), do: "group"

  def normalize_room_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
  end

  def normalize_room_name(_name), do: nil

  def normalize_room_display(name) when is_binary(name) do
    trimmed = String.trim(name)

    case String.downcase(trimmed) do
      "" -> trimmed
      downcased -> String.capitalize(downcased)
    end
  end

  def normalize_room_display(_name), do: nil

  def build_device_area_map(device_registry) do
    Enum.reduce(device_registry, %{}, fn device, acc ->
      id = fetch(device, :id)
      area_id = fetch(device, :area_id)

      if is_binary(id) and is_binary(area_id) do
        Map.put(acc, id, area_id)
      else
        acc
      end
    end)
  end

  def shared_room_for_members(members, light_room_by_id) do
    rooms =
      members
      |> Enum.map(&Map.get(light_room_by_id, &1))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case rooms do
      [room_id] -> room_id
      _ -> nil
    end
  end

  def mired_to_kelvin(mired) when is_binary(mired) do
    case Float.parse(mired) do
      {value, _rest} -> mired_to_kelvin(value)
      :error -> nil
    end
  end

  def mired_to_kelvin(mired) when (is_integer(mired) or is_float(mired)) and mired > 0 do
    round(1_000_000 / mired)
  end

  def mired_to_kelvin(_mired), do: nil

  def fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  def fetch(_map, _key), do: nil

  def extract_device_connection(light, type) do
    device = fetch(light, :device) || %{}
    connections = fetch(device, :connections) || []

    Enum.find_value(connections, fn
      [^type, value] -> value
      [value_type, value] when value_type == type -> value
      _ -> nil
    end)
  end

  def extract_device_identifier(light, type) do
    device = fetch(light, :device) || %{}
    identifiers = fetch(device, :identifiers) || []

    Enum.find_value(identifiers, fn
      [^type, value] -> value
      [value_type, value] when value_type == type -> value
      _ -> nil
    end)
  end
end
