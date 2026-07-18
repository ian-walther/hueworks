defmodule Hueworks.Import.Normalize.Caseta do
  @moduledoc false

  alias Hueworks.Import.Normalize

  def normalize(bridge, raw, _opts \\ %{}) do
    lights_raw = Normalize.fetch(raw, :lights) |> Normalize.normalize_list()

    {areas, area_map} = build_caseta_areas(lights_raw)

    lights =
      Enum.map(lights_raw, fn light ->
        area_source_id = Normalize.fetch(light, :area_id)
        name = Normalize.fetch(light, :name) || "Caseta Light"

        %{
          source: :caseta,
          source_id: Normalize.fetch(light, :zone_id),
          name: name,
          classification: "light",
          area_source_id: area_source_id,
          capabilities: normalize_caseta_capabilities(light),
          identifiers: %{"serial" => to_string(Normalize.fetch(light, :serial) || "")},
          metadata: %{
            "device_id" => Normalize.fetch(light, :device_id),
            "model" => Normalize.fetch(light, :model),
            "type" => Normalize.fetch(light, :type),
            "area_name" => Map.get(area_map, area_source_id)
          }
        }
      end)

    memberships = %{
      area_groups: [],
      area_lights:
        lights
        |> Enum.filter(& &1.area_source_id)
        |> Enum.map(fn light ->
          %{
            area_source_id: light.area_source_id,
            light_source_id: light.source_id
          }
        end),
      group_lights: []
    }

    Normalize.base_normalized(bridge, areas, [], lights, memberships)
  end

  defp normalize_caseta_capabilities(light) do
    type = Normalize.fetch(light, :type) || ""

    brightness =
      String.contains?(type, "Dimmer") or
        String.contains?(type, "Fan") or
        String.contains?(type, "Speed")

    %{
      brightness: brightness,
      color: false,
      color_temp: false,
      reported_kelvin_min: nil,
      reported_kelvin_max: nil
    }
  end

  defp build_caseta_areas(lights_raw) do
    areas =
      lights_raw
      |> Enum.reduce(%{}, fn light, acc ->
        area_id = Normalize.fetch(light, :area_id)
        name = extract_caseta_area_name(Normalize.fetch(light, :name))

        if is_binary(area_id) and is_binary(name) do
          Map.put_new(acc, area_id, name)
        else
          acc
        end
      end)

    area_list =
      Enum.map(areas, fn {id, name} ->
        %{
          source: :caseta,
          source_id: id,
          name: Normalize.normalize_area_display(name),
          normalized_name: Normalize.normalize_area_name(name),
          metadata: %{}
        }
      end)

    {area_list, areas}
  end

  defp extract_caseta_area_name(name) when is_binary(name) do
    case String.split(name, " / ", parts: 2) do
      [area, _rest] -> area
      _ -> nil
    end
  end

  defp extract_caseta_area_name(_name), do: nil
end
