defmodule Hueworks.BridgeOnboarding.Hue do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.Hue.{Device, Mdns, Pairing, VendorDiscovery}

  def discover(opts \\ []) do
    local = Keyword.get(opts, :local, Mdns)
    fallback = Keyword.get(opts, :fallback, VendorDiscovery)

    results = [safe_discover(local), safe_discover(fallback)]

    devices =
      results
      |> Enum.flat_map(fn
        {:ok, devices} when is_list(devices) -> devices
        _ -> []
      end)
      |> merge_devices()

    if devices == [] do
      {:error,
       "No Hue bridges were discovered. Check that HueWorks can reach the same LAN, then retry or use the manual address fallback."}
    else
      {:ok, devices}
    end
  end

  def pair(host, external_id, opts \\ []) do
    Pairing.pair(host, external_id, opts)
  end

  defp safe_discover(module) do
    module.discover()
  rescue
    _error -> {:error, :discovery_failed}
  catch
    :exit, _reason -> {:error, :discovery_failed}
  end

  defp merge_devices(devices) do
    devices
    |> Enum.map(&Device.normalize/1)
    |> Enum.reject(&is_nil(&1.host))
    |> Enum.reduce(%{}, fn device, acc ->
      Map.update(acc, Device.identity(device), device, &Device.merge(&1, device))
    end)
    |> Map.values()
    |> Enum.sort_by(fn device ->
      {is_nil(device.name), device.name || device.host, device.host}
    end)
  end
end
