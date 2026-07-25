defmodule Hueworks.BridgeOnboarding.Caseta.Device do
  @moduledoc false

  @enforce_keys [:host]
  defstruct [:id, :host, :name]

  def normalize(%__MODULE__{} = device) do
    %__MODULE__{
      device
      | id: normalize_text(device.id),
        host: normalize_text(device.host),
        name: normalize_text(device.name)
    }
  end

  def normalize(%{} = device) do
    normalize(%__MODULE__{
      id: Map.get(device, :id) || Map.get(device, "id"),
      host: Map.get(device, :host) || Map.get(device, "host"),
      name: Map.get(device, :name) || Map.get(device, "name")
    })
  end

  def normalize(_device), do: nil

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp normalize_text(value) when is_list(value), do: value |> to_string() |> normalize_text()
  defp normalize_text(_value), do: nil
end
