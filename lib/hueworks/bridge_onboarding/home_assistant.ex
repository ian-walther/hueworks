defmodule Hueworks.BridgeOnboarding.HomeAssistant do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.HomeAssistant.Device

  def discover(opts \\ []) do
    local = Keyword.get(opts, :local, __MODULE__.Mdns)

    case local.discover() do
      {:ok, devices} ->
        devices =
          devices
          |> Enum.map(&Device.normalize/1)
          |> Enum.reject(&is_nil(&1.host))
          |> Enum.uniq_by(&Device.identity/1)

        if devices == [] do
          {:error,
           "No Home Assistant instances were discovered on this network. Retry or use the manual address fallback."}
        else
          {:ok, devices}
        end

      {:error, _reason} ->
        {:error,
         "Home Assistant discovery was unavailable. Retry or use the manual address fallback."}
    end
  end
end
