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

  def normalize(bridge, raw) do
    areas = Normalize.fetch(raw, :areas) || []
    device_registry = Normalize.fetch(raw, :device_registry) || []
    lights_raw = Normalize.fetch(raw, :light_entities) || []
    groups_raw = Normalize.fetch(raw, :group_entities) || []

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

    lights =
      Enum.map(lights_raw, fn light ->
        name =
          Normalize.fetch(light, :name) ||
            Normalize.fetch(light, :friendly_name) ||
            Normalize.fetch(light, :entity_id) ||
            "HA Light"

        device_area_id =
          Normalize.fetch(light, :device_id)
          |> then(fn device_id -> if is_binary(device_id), do: Map.get(device_area_by_id, device_id), else: nil end)

        room_source_id = Normalize.fetch(light, :area_id) || device_area_id

        %{
          source: :ha,
          source_id: Normalize.fetch(light, :entity_id),
          name: name,
          room_source_id: room_source_id,
          capabilities: normalize_ha_capabilities(light),
          identifiers: %{
            "mac" => Normalize.extract_device_connection(light, "mac"),
            "serial" => Normalize.extract_device_identifier(light, "serial")
          },
          metadata: %{
            "entity_id" => Normalize.fetch(light, :entity_id),
            "platform" => Normalize.fetch(light, :platform),
            "device_id" => Normalize.fetch(light, :device_id),
            "source" => Normalize.fetch(light, :source)
          }
        }
      end)

    light_capabilities_by_id =
      Map.new(lights, fn light -> {light.source_id, light.capabilities} end)

    light_room_by_id =
      Map.new(lights, fn light -> {light.source_id, light.room_source_id} end)

    groups =
      Enum.map(groups_raw, fn group ->
        members = Normalize.fetch(group, :members) || []
        room_source_id = Normalize.shared_room_for_members(members, light_room_by_id)
        capabilities = Normalize.aggregate_capabilities(members, light_capabilities_by_id)

        %{
          source: :ha,
          source_id: Normalize.fetch(group, :entity_id),
          name: Normalize.fetch(group, :name) || Normalize.fetch(group, :entity_id) || "HA Group",
          room_source_id: Normalize.fetch(group, :area_id) || room_source_id,
          type: "group",
          capabilities: capabilities,
          metadata: %{
            "platform" => Normalize.fetch(group, :platform),
            "members" => members
          }
        }
      end)

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
      group_lights:
        groups
        |> Enum.flat_map(fn group ->
          members = Normalize.fetch(group, :metadata)["members"] || []

          Enum.map(members, fn light_id ->
            %{group_source_id: group.source_id, light_source_id: light_id}
          end)
        end)
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
end
