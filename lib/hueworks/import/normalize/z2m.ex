defmodule Hueworks.Import.Normalize.Z2M do
  @moduledoc false

  alias Hueworks.Import.Normalize

  @color_temp_keys MapSet.new(["color_temp", "color_temp_startup"])
  @color_keys MapSet.new(["color", "color_hs", "color_xy", "hue", "saturation"])

  def normalize(bridge, raw, _opts \\ %{}) do
    devices_raw = Normalize.fetch(raw, :devices) |> Normalize.normalize_list()
    groups_raw = Normalize.fetch(raw, :groups) |> Normalize.normalize_list()

    lights =
      devices_raw
      |> Enum.map(&normalize_light/1)
      |> Enum.filter(&is_map/1)

    light_capabilities_by_id =
      Map.new(lights, fn light -> {light.source_id, light.capabilities} end)

    indexes = %{
      by_source_id: Map.new(lights, fn light -> {light.source_id, light.source_id} end),
      by_ieee:
        Map.new(lights, fn light ->
          {get_in(light, [:identifiers, "ieee"]), light.source_id}
        end)
        |> Enum.reject(fn {key, _value} -> not is_binary(key) or key == "" end)
        |> Map.new(),
      by_name:
        Map.new(lights, fn light ->
          {Normalize.fetch(light, :name), light.source_id}
        end)
        |> Enum.reject(fn {key, _value} -> not is_binary(key) or key == "" end)
        |> Map.new()
    }

    groups =
      groups_raw
      |> Enum.map(&normalize_group(&1, indexes, light_capabilities_by_id))
      |> Enum.filter(&is_map/1)

    memberships = %{
      room_groups: [],
      room_lights: [],
      group_lights: group_lights(groups)
    }

    Normalize.base_normalized(bridge, [], groups, lights, memberships)
  end

  defp normalize_light(device) do
    source_id =
      Normalize.fetch(device, :friendly_name) ||
        Normalize.fetch(device, :ieee_address) ||
        Normalize.fetch(device, :id)

    source_id = Normalize.normalize_source_id(source_id)

    cond do
      not is_binary(source_id) ->
        nil

      coordinator?(device) ->
        nil

      true ->
        capabilities = normalize_capabilities(device)

        if include_as_light?(device, capabilities) do
          definition = Normalize.fetch(device, :definition) |> Normalize.normalize_map()

          %{
            source: :z2m,
            source_id: source_id,
            name: Normalize.fetch(device, :friendly_name) || source_id,
            classification: "light",
            room_source_id: nil,
            capabilities: capabilities,
            identifiers: %{
              "ieee" => Normalize.fetch(device, :ieee_address)
            },
            metadata: %{
              "ieee_address" => Normalize.fetch(device, :ieee_address),
              "type" => Normalize.fetch(device, :type),
              "manufacturer" => Normalize.fetch(definition, :vendor),
              "model" => Normalize.fetch(definition, :model),
              "description" => Normalize.fetch(definition, :description),
              "friendly_name" => Normalize.fetch(device, :friendly_name),
              "definition" => definition
            }
          }
        else
          nil
        end
    end
  end

  defp normalize_group(group, indexes, light_capabilities_by_id) do
    source_id =
      Normalize.fetch(group, :friendly_name) ||
        Normalize.fetch(group, :id)

    source_id = Normalize.normalize_source_id(source_id)

    if is_binary(source_id) do
      members = resolve_group_members(group, indexes)
      capabilities = Normalize.aggregate_capabilities(members, light_capabilities_by_id)

      %{
        source: :z2m,
        source_id: source_id,
        name: Normalize.fetch(group, :friendly_name) || "Z2M Group #{source_id}",
        classification: "group",
        room_source_id: nil,
        type: "group",
        capabilities: capabilities,
        metadata: %{
          "id" => Normalize.fetch(group, :id),
          "friendly_name" => Normalize.fetch(group, :friendly_name),
          "members" => members,
          "raw" => group
        }
      }
    else
      nil
    end
  end

  defp resolve_group_members(group, indexes) do
    group
    |> Normalize.fetch(:members)
    |> Normalize.normalize_list()
    |> Enum.flat_map(&member_tokens/1)
    |> Enum.map(&resolve_member_token(&1, indexes))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp member_tokens(member) when is_binary(member), do: [member]

  defp member_tokens(member) when is_map(member) do
    device = Normalize.fetch(member, :device) |> Normalize.normalize_map()

    [
      Normalize.fetch(member, :friendly_name),
      Normalize.fetch(member, :ieee_address),
      Normalize.fetch(member, :id),
      Normalize.fetch(member, :device),
      Normalize.fetch(device, :friendly_name),
      Normalize.fetch(device, :ieee_address)
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp member_tokens(_member), do: []

  defp resolve_member_token(token, indexes) do
    cond do
      Map.has_key?(indexes.by_source_id, token) -> Map.get(indexes.by_source_id, token)
      Map.has_key?(indexes.by_name, token) -> Map.get(indexes.by_name, token)
      Map.has_key?(indexes.by_ieee, token) -> Map.get(indexes.by_ieee, token)
      true -> nil
    end
  end

  defp group_lights(groups) do
    Enum.flat_map(groups, fn group ->
      members = get_in(group, [:metadata, "members"]) || []

      Enum.map(members, fn light_source_id ->
        %{group_source_id: group.source_id, light_source_id: light_source_id}
      end)
    end)
  end

  defp include_as_light?(device, capabilities) do
    exposes = device_exposes(device)

    has_light_expose =
      Enum.any?(exposes, fn expose ->
        Normalize.fetch(expose, :type) == "light"
      end)

    has_light_expose or capabilities.brightness or capabilities.color_temp or capabilities.color
  end

  defp normalize_capabilities(device) do
    exposes = flatten_exposes(device_exposes(device))

    color_temp_feature =
      Enum.find(exposes, fn expose ->
        key = feature_key(expose)
        MapSet.member?(@color_temp_keys, key)
      end)

    {reported_min_kelvin, reported_max_kelvin} = normalize_color_temp_range(color_temp_feature)

    %{
      brightness: Enum.any?(exposes, &(feature_key(&1) == "brightness")),
      color: Enum.any?(exposes, &MapSet.member?(@color_keys, feature_key(&1))),
      color_temp: Enum.any?(exposes, &MapSet.member?(@color_temp_keys, feature_key(&1))),
      reported_kelvin_min: reported_min_kelvin,
      reported_kelvin_max: reported_max_kelvin
    }
  end

  defp normalize_color_temp_range(nil), do: {nil, nil}

  defp normalize_color_temp_range(feature) do
    min_value = numeric_value(Normalize.fetch(feature, :value_min))
    max_value = numeric_value(Normalize.fetch(feature, :value_max))

    cond do
      is_number(min_value) and is_number(max_value) and min_value > 0 and max_value > 0 and
          max_value <= 1000 ->
        {Normalize.mired_to_kelvin(max_value), Normalize.mired_to_kelvin(min_value)}

      is_number(min_value) and is_number(max_value) and min_value > 0 and max_value > 0 ->
        {round(min(min_value, max_value)), round(max(min_value, max_value))}

      true ->
        {nil, nil}
    end
  end

  defp flatten_exposes(exposes) when is_list(exposes) do
    Enum.flat_map(exposes, fn expose ->
      child_features = Normalize.fetch(expose, :features) |> Normalize.normalize_list()

      if child_features == [] do
        [expose]
      else
        [expose | flatten_exposes(child_features)]
      end
    end)
  end

  defp flatten_exposes(_exposes), do: []

  defp device_exposes(device) do
    device
    |> Normalize.fetch(:definition)
    |> Normalize.normalize_map()
    |> Normalize.fetch(:exposes)
    |> Normalize.normalize_list()
  end

  defp feature_key(feature) do
    Normalize.fetch(feature, :property) ||
      Normalize.fetch(feature, :name) ||
      Normalize.fetch(feature, :type) ||
      ""
  end

  defp coordinator?(device) do
    Normalize.fetch(device, :type) == "Coordinator"
  end

  defp numeric_value(value) when is_integer(value), do: value
  defp numeric_value(value) when is_float(value), do: value

  defp numeric_value(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp numeric_value(_value), do: nil
end
