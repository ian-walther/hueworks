defmodule Hueworks.Import.Normalize.Hue do
  @moduledoc false

  alias Hueworks.Import.Normalize

  def normalize(bridge, raw, _opts \\ %{}) do
    raw_groups = Normalize.fetch(raw, :groups) |> Normalize.normalize_map()
    raw_lights = Normalize.fetch(raw, :lights) |> Normalize.normalize_map()

    rooms =
      raw_groups
      |> Enum.filter(fn {_id, group} -> Normalize.fetch(group, :type) == "Room" end)
      |> Enum.map(fn {id, group} ->
        name = Normalize.fetch(group, :name) || "Room #{id}"

        %{
          source: :hue,
          source_id: id,
          name: Normalize.normalize_room_display(name),
          normalized_name: Normalize.normalize_room_name(name),
          metadata: %{"type" => Normalize.fetch(group, :type)}
        }
      end)

    light_room_map =
      raw_groups
      |> Enum.filter(fn {_id, group} -> Normalize.fetch(group, :type) == "Room" end)
      |> Enum.reduce(%{}, fn {room_id, group}, acc ->
        lights = Normalize.fetch(group, :lights) || []

        Enum.reduce(lights, acc, fn light_id, inner ->
          Map.put(inner, light_id, room_id)
        end)
      end)

    lights =
      raw_lights
      |> Enum.map(fn {id, light} ->
        capabilities = normalize_hue_light_capabilities(light)

        %{
          source: :hue,
          source_id: id,
          name: Normalize.fetch(light, :name) || "Hue Light #{id}",
          classification: "light",
          room_source_id: Map.get(light_room_map, id),
          capabilities: capabilities,
          identifiers: %{"mac" => Normalize.fetch(light, :mac)},
          metadata: %{
            "bridge_host" => bridge.host,
            "uniqueid" => Normalize.fetch(light, :uniqueid),
            "modelid" => Normalize.fetch(light, :modelid),
            "productname" => Normalize.fetch(light, :productname),
            "type" => Normalize.fetch(light, :type)
          }
        }
      end)

    light_capabilities_by_id =
      Map.new(lights, fn light -> {light.source_id, light.capabilities} end)

    groups =
      raw_groups
      |> Enum.map(fn {id, group} ->
        group_type = Normalize.fetch(group, :type)
        normalized_type = Normalize.normalize_group_type(group_type)
        member_ids = Normalize.fetch(group, :lights) || []
        capabilities = Normalize.aggregate_capabilities(member_ids, light_capabilities_by_id)
        classification = hue_group_classification(group_type)

        %{
          source: :hue,
          source_id: id,
          name: Normalize.fetch(group, :name) || "Hue Group #{id}",
          classification: classification,
          room_source_id: if(group_type == "Room", do: id, else: nil),
          type: normalized_type,
          capabilities: capabilities,
          metadata: %{
            "bridge_host" => bridge.host,
            "type" => group_type
          }
        }
      end)

    memberships = %{
      room_groups:
        groups
        |> Enum.filter(fn group -> group.room_source_id == group.source_id end)
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
        raw_groups
        |> Enum.flat_map(fn {group_id, group} ->
          (Normalize.fetch(group, :lights) || [])
          |> Enum.map(fn light_id ->
            %{group_source_id: group_id, light_source_id: light_id}
          end)
        end)
    }

    Normalize.base_normalized(bridge, rooms, groups, lights, memberships)
  end

  defp hue_group_classification("Room"), do: "group_room"
  defp hue_group_classification("Zone"), do: "group_zone"
  defp hue_group_classification("LightGroup"), do: "group"
  defp hue_group_classification(_type), do: "group"

  defp normalize_hue_light_capabilities(light) do
    caps = Normalize.fetch(light, :capabilities) || %{}
    control = Normalize.fetch(caps, :control) || %{}
    ct = Normalize.fetch(control, :ct) || %{}

    {min_kelvin, max_kelvin} =
      case {Normalize.fetch(ct, :min), Normalize.fetch(ct, :max)} do
        {min_mired, max_mired} when is_number(min_mired) and is_number(max_mired) ->
          {Normalize.mired_to_kelvin(max_mired), Normalize.mired_to_kelvin(min_mired)}

        _ ->
          {nil, nil}
      end

    %{
      brightness: !!Normalize.fetch(caps, :brightness),
      color: !!Normalize.fetch(caps, :color),
      color_temp: !!Normalize.fetch(caps, :color_temp),
      reported_kelvin_min: min_kelvin,
      reported_kelvin_max: max_kelvin
    }
  end

end
