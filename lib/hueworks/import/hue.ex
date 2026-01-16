defmodule Hueworks.Import.Hue do
  @moduledoc """
  Import helpers for Hue exports.
  """

  alias Hueworks.Import.Persist

  def import(export) do
    %{bridges: bridges, lights: lights} = normalize(export)

    Enum.each(bridges, fn %{lights: bridge_lights} = bridge_payload ->
      bridge = Persist.upsert_bridge(bridge_payload.bridge)

      Enum.each(bridge_lights, fn light_attrs ->
        attrs = Map.merge(light_attrs, %{bridge_id: bridge.id})
        Persist.upsert_light(attrs)
      end)
    end)

    %{bridges: bridges, lights: lights}
  end

  def normalize(export) do
    bridges = export["bridges"] || export[:bridges] || []

    normalized =
      Enum.map(bridges, fn bridge ->
        host = bridge["host"] || bridge[:host]
        name = bridge["name"] || bridge[:name] || host
        lights = normalize_lights(bridge["lights"] || bridge[:lights] || %{}, host)

        %{
          bridge: %{
            type: :hue,
            name: name,
            host: host,
            credentials: %{}
          },
          lights: lights
        }
      end)

    %{
      bridges: normalized,
      lights: Enum.flat_map(normalized, & &1.lights)
    }
  end

  defp normalize_lights(lights, bridge_host) when is_map(lights) do
    lights
    |> Enum.map(fn {id, light} ->
      source_id = light["id"] || light[:id] || id

      %{
        name: light["name"],
        source: :hue,
        source_id: to_string(source_id),
        enabled: true,
        metadata: %{
          "bridge_host" => bridge_host,
          "uniqueid" => light["uniqueid"],
          "mac" => light["mac"],
          "modelid" => light["modelid"],
          "productname" => light["productname"],
          "type" => light["type"],
          "capabilities" => light["capabilities"]
        }
      }
    end)
  end

  defp normalize_lights(_lights, _bridge_host), do: []
end
