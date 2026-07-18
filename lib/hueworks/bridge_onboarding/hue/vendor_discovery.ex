defmodule Hueworks.BridgeOnboarding.Hue.VendorDiscovery do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.Hue.Device

  @url "https://discovery.meethue.com/"

  def discover do
    http = Application.get_env(:hueworks, :hue_discovery_http_module, HTTPoison)
    url = Application.get_env(:hueworks, :hue_discovery_url, @url)

    case http.get(url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> parse(body)
      {:ok, %HTTPoison.Response{}} -> {:error, :vendor_discovery_failed}
      {:error, _reason} -> {:error, :vendor_discovery_failed}
    end
  end

  def parse(body) when is_binary(body) do
    with {:ok, entries} when is_list(entries) <- Jason.decode(body) do
      devices =
        entries
        |> Enum.map(&device_from_entry/1)
        |> Enum.reject(&is_nil/1)

      {:ok, devices}
    else
      _ -> {:error, :invalid_vendor_discovery_response}
    end
  end

  defp device_from_entry(%{"internalipaddress" => host} = entry) when is_binary(host) do
    %Device{
      id: entry["id"],
      host: host,
      sources: [:vendor]
    }
  end

  defp device_from_entry(_entry), do: nil
end
