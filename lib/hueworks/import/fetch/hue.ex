defmodule Hueworks.Import.Fetch.Hue do
  @moduledoc """
  Fetch minimal Hue data needed for import.
  """

  require Logger

  alias Hueworks.Import.Fetch.Common
  alias Hueworks.Schemas.Bridge

  def fetch do
    bridges = Common.load_enabled_bridges(:hue)

    bridges =
      Enum.map(bridges, &fetch_bridge(&1, true))

    %{
      bridges: bridges,
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def fetch_for_bridge(bridge) do
    fetch_bridge(bridge, false)
  end


  defp fetch_bridge(bridge, log?) do
    api_key = Bridge.credentials_struct(bridge).api_key

    if Common.invalid_credential?(api_key) do
      raise "Missing Hue api_key for bridge #{bridge.name} (#{bridge.host})"
    end

    if log? do
      Logger.info("Fetching Hue lights from #{bridge.name}...")
    end

    lights =
      fetch_endpoint(bridge.host, api_key, "/lights")
      |> add_hue_macs()
      |> simplify_hue_lights()

    groups =
      fetch_endpoint(bridge.host, api_key, "/groups")
      |> simplify_hue_groups()

    %{
      name: bridge.name,
      host: bridge.host,
      lights: lights,
      groups: groups
    }
  end

  defp fetch_endpoint(host, api_key, endpoint) do
    url = "http://#{host}/api/#{api_key}#{endpoint}"

    case HTTPoison.get(url, [], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> data
          {:error, _reason} -> %{error: "Failed to decode JSON"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        %{error: "HTTP #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        %{error: inspect(reason)}
    end
  end

  defp add_hue_macs(lights) when is_map(lights) do
    Map.new(lights, fn {id, light} ->
      mac = hue_uniqueid_to_mac(light["uniqueid"])
      {id, Map.put(light, "mac", mac)}
    end)
  end

  defp add_hue_macs(lights), do: lights

  defp hue_uniqueid_to_mac(uniqueid) when is_binary(uniqueid) do
    uniqueid
    |> String.split("-", parts: 2)
    |> List.first()
  end

  defp hue_uniqueid_to_mac(_uniqueid), do: nil

  defp simplify_hue_lights(lights) when is_map(lights) do
    Map.new(lights, fn {id, light} ->
      control = get_in(light, ["capabilities", "control"]) || %{}
      ct = get_in(control, ["ct"]) || %{}
      state = light["state"] || %{}

      supports_brightness = Map.has_key?(state, "bri")

      supports_color =
        Map.has_key?(control, "colorgamut") or Map.has_key?(control, "colorgamuttype")

      supports_color_temp = Map.has_key?(control, "ct")
      ct_min = ct["min"]
      ct_max = ct["max"]

      {id,
       %{
         id: id,
         name: light["name"],
         uniqueid: light["uniqueid"],
         mac: light["mac"],
         modelid: light["modelid"],
         productname: light["productname"],
         type: light["type"],
         capabilities: %{
           brightness: supports_brightness,
           color: supports_color,
           color_temp: supports_color_temp,
           control: %{
             ct: %{
               min: ct_min,
               max: ct_max
             }
           }
         }
       }}
    end)
  end

  defp simplify_hue_lights(lights), do: lights

  defp simplify_hue_groups(groups) when is_map(groups) do
    Map.new(groups, fn {id, group} ->
      {id,
       %{
         id: id,
         name: group["name"],
         type: group["type"],
         lights: group["lights"] || []
       }}
    end)
  end

  defp simplify_hue_groups(groups), do: groups

end
