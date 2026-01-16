defmodule Hueworks.Import.Caseta do
  @moduledoc """
  Import helpers for Lutron Caseta exports.
  """

  alias Hueworks.Import.Persist

  def import(export) do
    %{bridge: bridge_attrs, lights: lights} = normalize(export)
    bridge = Persist.upsert_bridge(bridge_attrs)

    Enum.each(lights, fn light_attrs ->
      attrs = Map.merge(light_attrs, %{bridge_id: bridge.id})
      Persist.upsert_light(attrs)
    end)

    %{bridge: bridge_attrs, lights: lights}
  end

  def normalize(export) do
    bridge_host = export["bridge_ip"] || export[:bridge_ip]

    lights =
      export
      |> get_in(["lights"]) ||
        export[:lights] ||
        []

    %{
      bridge: %{
        type: :caseta,
        name: "Caseta Bridge",
        host: bridge_host,
        credentials: %{}
      },
      lights: normalize_lights(lights)
    }
  end

  defp normalize_lights(lights) when is_list(lights) do
    Enum.map(lights, fn light ->
      %{
        name: light["name"],
        source: :caseta,
        source_id: to_string(light["zone_id"]),
        enabled: true,
        metadata: %{
          "device_id" => light["device_id"],
          "area_id" => light["area_id"],
          "type" => light["type"],
          "model" => light["model"],
          "serial" => light["serial"]
        }
      }
    end)
  end

  defp normalize_lights(_lights), do: []
end
