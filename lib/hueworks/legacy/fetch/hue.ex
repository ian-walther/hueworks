defmodule Hueworks.Legacy.Fetch.Hue do
  @moduledoc """
  Fetch minimal Hue data needed for import.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Schemas.Bridge
  alias Hueworks.Repo

  def fetch do
    bridges = load_bridges(:hue)

    bridges =
      Enum.map(bridges, fn bridge ->
        api_key = bridge.credentials["api_key"]

        if is_nil(api_key) or api_key == "" do
          raise "Missing Hue api_key for bridge #{bridge.name} (#{bridge.host})"
        end

        IO.puts("Fetching Hue lights from #{bridge.name}...")

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
      end)

    %{
      bridges: bridges,
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
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

  defp load_bridges(type) do
    Repo.all(from(b in Bridge, where: b.type == ^type and b.enabled == true))
  end
end
