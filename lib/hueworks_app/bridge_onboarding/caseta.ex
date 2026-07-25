defmodule Hueworks.BridgeOnboarding.Caseta do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.Caseta.{Device, Mdns}

  def discover(opts \\ []) do
    module = Keyword.get(opts, :mdns, Mdns)
    external_id = opts |> Keyword.get(:external_id) |> normalize_external_id()

    devices =
      discover_devices(module, external_id)
      |> case do
        {:ok, devices} when is_list(devices) -> devices
        _ -> []
      end
      |> Enum.map(&Device.normalize/1)
      |> Enum.reject(&(is_nil(&1) or is_nil(&1.host)))
      |> Enum.uniq_by(&(&1.id || &1.host))

    case devices do
      [] -> {:error, "The selected Caseta bridge was not found. Enter its address manually."}
      found -> {:ok, found}
    end
  end

  defp discover_devices(module, external_id) when is_binary(external_id) do
    case module.resolve(external_id) do
      {:ok, device} -> {:ok, [device]}
      _other -> module.discover()
    end
  end

  defp discover_devices(module, _external_id), do: module.discover()

  defp normalize_external_id(value) when is_binary(value) do
    id = value |> String.trim() |> String.downcase()
    if Regex.match?(~r/^[0-9a-f]{8}$/, id), do: id
  end

  defp normalize_external_id(_value), do: nil
end
