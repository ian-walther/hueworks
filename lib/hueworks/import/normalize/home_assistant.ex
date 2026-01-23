defmodule Hueworks.Import.Normalize.HomeAssistant do
  @moduledoc false

  alias Hueworks.Import.Normalize

  @brightness_color_modes ~w(
    brightness
    color_temp
    hs
    rgb
    rgbw
    rgbww
    xy
  )

  @color_color_modes ~w(hs rgb rgbw rgbww xy)
  @temp_color_modes ~w(color_temp)

  def normalize(bridge, raw, _opts \\ %{}) do
    areas = Normalize.fetch(raw, :areas) || []
    device_registry = Normalize.fetch(raw, :device_registry) || []
    lights_raw = Normalize.fetch(raw, :light_entities) || []
    groups_raw = Normalize.fetch(raw, :group_entities) || []
    light_states = Normalize.fetch(raw, :light_states) || %{}
    zha_groups = Normalize.fetch(raw, :zha_groups) || []
    state_members_by_entity_id = state_members_by_entity_id(light_states)
    zha_members_by_entity_id = zha_members_by_entity_id(zha_groups, lights_raw)

    rooms =
      Enum.map(areas, fn area ->
        name = Normalize.fetch(area, :name) || Normalize.fetch(area, :area_id) || "Room"

        %{
          source: :ha,
          source_id: Normalize.fetch(area, :area_id),
          name: Normalize.normalize_room_display(name),
          normalized_name: Normalize.normalize_room_name(name),
          metadata: %{"raw" => area}
        }
      end)

    device_area_by_id = Normalize.build_device_area_map(device_registry)

    {lights, derived_groups} =
      lights_raw
      |> Enum.reduce({[], []}, fn light, {lights_acc, groups_acc} ->
        name =
          Normalize.fetch(light, :name) ||
            Normalize.fetch(light, :friendly_name) ||
            Normalize.fetch(light, :entity_id) ||
            "HA Light"

        device_area_id =
          Normalize.fetch(light, :device_id)
          |> then(fn device_id -> if is_binary(device_id), do: Map.get(device_area_by_id, device_id), else: nil end)

        room_source_id = Normalize.fetch(light, :area_id) || device_area_id

        platform = Normalize.fetch(light, :platform)
        device = Normalize.fetch(light, :device) || %{}

        members =
          Normalize.fetch(light, :members) ||
            Map.get(state_members_by_entity_id, Normalize.fetch(light, :entity_id)) ||
            Map.get(zha_members_by_entity_id, Normalize.fetch(light, :entity_id))

        classification = ha_light_classification(platform)

        base_light = %{
          source: :ha,
          source_id: Normalize.fetch(light, :entity_id),
          name: name,
          classification: classification,
          room_source_id: room_source_id,
          capabilities: normalize_ha_capabilities(light),
          identifiers: %{
            "mac" => Normalize.extract_device_connection(light, "mac"),
            "serial" => Normalize.extract_device_identifier(light, "serial")
          },
          metadata: %{
            "entity_id" => Normalize.fetch(light, :entity_id),
            "platform" => platform,
            "device_id" => Normalize.fetch(light, :device_id),
            "source" => Normalize.fetch(light, :source),
            "unique_id" => Normalize.fetch(light, :unique_id),
            "members" => members,
            "is_template" => platform == "template",
            "device_model" => Normalize.fetch(device, :model),
            "device_name" => Normalize.fetch(device, :name),
            "device_manufacturer" => Normalize.fetch(device, :manufacturer)
          }
        }
        group = maybe_group_from_light(base_light, members)

        cond do
          platform in ["group", "light_group"] ->
            {lights_acc, groups_acc}

          is_map(group) ->
            {lights_acc, [group | groups_acc]}

          true ->
            {[base_light | lights_acc], groups_acc}
        end
      end)

    lights = Enum.reverse(lights)
    derived_groups = Enum.reverse(derived_groups)

    light_capabilities_by_id =
      Map.new(lights, fn light -> {light.source_id, light.capabilities} end)

    light_room_by_id =
      Map.new(lights, fn light -> {light.source_id, light.room_source_id} end)

    groups =
      groups_raw
      |> Enum.map(fn group ->
        members = Normalize.fetch(group, :members) || []
        room_source_id = Normalize.shared_room_for_members(members, light_room_by_id)
        capabilities = Normalize.aggregate_capabilities(members, light_capabilities_by_id)

        %{
          source: :ha,
          source_id: Normalize.fetch(group, :entity_id),
          name: Normalize.fetch(group, :name) || Normalize.fetch(group, :entity_id) || "HA Group",
          classification: "ha_group",
          room_source_id: Normalize.fetch(group, :area_id) || room_source_id,
          type: "group",
          capabilities: capabilities,
          metadata: %{
            "platform" => Normalize.fetch(group, :platform),
            "members" => members
          }
        }
      end)
      |> Kernel.++(derived_groups)

    memberships = %{
      room_groups:
        groups
        |> Enum.filter(& &1.room_source_id)
        |> Enum.map(fn group ->
          %{
            room_source_id: group.room_source_id,
            group_source_id: group.source_id
          }
        end),
      room_lights:
        lights
        |> Enum.filter(& &1.room_source_id)
        |> Enum.map(fn light ->
          %{
            room_source_id: light.room_source_id,
            light_source_id: light.source_id
          }
        end),
      group_lights: group_lights_from_groups(groups)
    }

    Normalize.base_normalized(bridge, rooms, groups, lights, memberships)
  end

  defp normalize_ha_capabilities(light) do
    modes = Normalize.fetch(light, :supported_color_modes) || []
    temp_range = Normalize.fetch(light, :temp_range) || %{}

    {min_kelvin, max_kelvin} =
      cond do
        is_number(Normalize.fetch(temp_range, :min_kelvin)) and
            is_number(Normalize.fetch(temp_range, :max_kelvin)) ->
          {round(Normalize.fetch(temp_range, :min_kelvin)), round(Normalize.fetch(temp_range, :max_kelvin))}

        is_number(Normalize.fetch(temp_range, :min_mireds)) and
            is_number(Normalize.fetch(temp_range, :max_mireds)) ->
          {Normalize.mired_to_kelvin(Normalize.fetch(temp_range, :max_mireds)),
           Normalize.mired_to_kelvin(Normalize.fetch(temp_range, :min_mireds))}

        true ->
          {nil, nil}
      end

    %{
      brightness: Enum.any?(modes, &(&1 in @brightness_color_modes)),
      color: Enum.any?(modes, &(&1 in @color_color_modes)),
      color_temp: Enum.any?(modes, &(&1 in @temp_color_modes)),
      reported_kelvin_min: min_kelvin,
      reported_kelvin_max: max_kelvin
    }
  end

  defp maybe_group_from_light(light, members) do
    metadata = Normalize.fetch(light, :metadata) || %{}
    platform = Normalize.fetch(metadata, :platform)
    device_model = Normalize.fetch(metadata, :device_model)
    unique_id = Normalize.fetch(metadata, :unique_id)
    source = Normalize.fetch(light, :source)
    members_list = if is_list(members), do: members, else: []

    cond do
      source != :ha ->
        nil

      platform == "hue" and device_model in ["Room", "Zone"] and members_list != [] ->
        build_group_from_light(light, members_list, "hue_group")

      platform == "zha" and is_binary(unique_id) and String.starts_with?(unique_id, "light_zha_group_") ->
        build_group_from_light(light, members_list, "zha_group")

      true ->
        nil
    end
  end

  defp build_group_from_light(light, members, group_type) do
    metadata = Normalize.fetch(light, :metadata) || %{}

    %{
      source: :ha,
      source_id: Normalize.fetch(light, :source_id),
      name: Normalize.fetch(light, :name) || "HA Group",
      classification: group_type,
      room_source_id: Normalize.fetch(light, :room_source_id),
      type: "group",
      capabilities: Normalize.fetch(light, :capabilities) || %{},
      metadata:
        metadata
        |> Map.put("members", members)
        |> Map.put("type", group_type)
    }
  end

  defp group_lights_from_groups(groups) do
    Enum.flat_map(groups, fn group ->
      members = Normalize.fetch(group, :metadata)["members"] || []

      Enum.map(members, fn light_id ->
        %{group_source_id: group.source_id, light_source_id: light_id}
      end)
    end)
  end

  defp ha_light_classification("template"), do: "template"
  defp ha_light_classification("zha"), do: "zha_light"
  defp ha_light_classification(_platform), do: "light"

  defp state_members_by_entity_id(light_states) when is_map(light_states) do
    Enum.reduce(light_states, %{}, fn {entity_id, attrs}, acc ->
      members = extract_members(attrs)

      if is_binary(entity_id) and is_list(members) do
        Map.put(acc, entity_id, members)
      else
        acc
      end
    end)
  end

  defp state_members_by_entity_id(light_states) when is_list(light_states) do
    Enum.reduce(light_states, %{}, fn state, acc ->
      entity_id = Normalize.fetch(state, :entity_id)
      attrs = Normalize.fetch(state, :attributes) || %{}
      members = extract_members(attrs)

      if is_binary(entity_id) and is_list(members) do
        Map.put(acc, entity_id, members)
      else
        acc
      end
    end)
  end

  defp state_members_by_entity_id(_light_states), do: %{}

  defp extract_members(attrs) when is_map(attrs) do
    Normalize.fetch(attrs, :entity_id) ||
      Normalize.fetch(attrs, :entities) ||
      Normalize.fetch(attrs, :members)
  end

  defp extract_members(_attrs), do: nil

  defp zha_members_by_entity_id(zha_groups, lights_raw) do
    entity_by_group_id = zha_group_entity_by_group_id(lights_raw)
    entity_by_ieee = zha_entity_by_ieee(lights_raw)

    Enum.reduce(zha_groups, %{}, fn group, acc ->
      group_id = Normalize.fetch(group, :group_id)
      group_entity_id = Map.get(entity_by_group_id, group_id)
      members = zha_member_entities(group, entity_by_ieee)

      if is_binary(group_entity_id) do
        Map.put(acc, group_entity_id, members)
      else
        acc
      end
    end)
  end

  defp zha_group_entity_by_group_id(lights_raw) do
    Enum.reduce(lights_raw, %{}, fn light, acc ->
      unique_id = Normalize.fetch(light, :unique_id)

      case zha_group_id_from_unique_id(unique_id) do
        nil ->
          acc

        group_id ->
          Map.put(acc, group_id, Normalize.fetch(light, :entity_id))
      end
    end)
  end

  defp zha_group_id_from_unique_id(unique_id) when is_binary(unique_id) do
    case Regex.run(~r/^light_zha_group_0x([0-9a-fA-F]+)$/, unique_id) do
      [_, hex] ->
        case Integer.parse(hex, 16) do
          {value, _} -> value
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp zha_group_id_from_unique_id(_unique_id), do: nil

  defp zha_entity_by_ieee(lights_raw) do
    Enum.reduce(lights_raw, %{}, fn light, acc ->
      device = Normalize.fetch(light, :device) || %{}
      identifiers = Normalize.fetch(device, :identifiers) || []

      Enum.reduce(identifiers, acc, fn
        ["zha", ieee], inner when is_binary(ieee) ->
          Map.update(inner, ieee, [Normalize.fetch(light, :entity_id)], fn list ->
            [Normalize.fetch(light, :entity_id) | list]
          end)

        _other, inner ->
          inner
      end)
    end)
  end

  defp zha_member_entities(group, entity_by_ieee) do
    members = Normalize.fetch(group, :members) || []

    members
    |> Enum.flat_map(fn member ->
      ieee = Normalize.fetch(member, :ieee) || Normalize.fetch(member, :device_ieee)
      Map.get(entity_by_ieee, ieee, [])
    end)
    |> Enum.uniq()
  end
end
