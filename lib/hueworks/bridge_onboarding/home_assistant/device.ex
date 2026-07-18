defmodule Hueworks.BridgeOnboarding.HomeAssistant.Device do
  @moduledoc false

  @enforce_keys [:host, :port]
  defstruct [:id, :host, :port, :name]

  def normalize(%__MODULE__{} = device) do
    %__MODULE__{
      device
      | id: normalize_text(device.id),
        host: normalize_text(device.host),
        name: normalize_text(device.name)
    }
  end

  def identity(%__MODULE__{id: id}) when is_binary(id), do: {:id, String.downcase(id)}
  def identity(%__MODULE__{} = device), do: {:endpoint, endpoint(device)}

  def endpoint(%__MODULE__{host: host, port: port}), do: "#{host}:#{port}"

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
