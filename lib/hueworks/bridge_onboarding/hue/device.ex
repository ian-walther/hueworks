defmodule Hueworks.BridgeOnboarding.Hue.Device do
  @moduledoc false

  @enforce_keys [:host]
  defstruct [:id, :host, :name, sources: []]

  def normalize(%__MODULE__{} = device) do
    %__MODULE__{
      device
      | id: normalize_id(device.id),
        host: normalize_text(device.host),
        name: normalize_text(device.name),
        sources: normalize_sources(device.sources)
    }
  end

  def merge(%__MODULE__{} = left, %__MODULE__{} = right) do
    left = normalize(left)
    right = normalize(right)

    %__MODULE__{
      id: left.id || right.id,
      host: left.host || right.host,
      name: left.name || right.name,
      sources: normalize_sources(left.sources ++ right.sources)
    }
  end

  def identity(%__MODULE__{id: id}) when is_binary(id), do: {:id, normalize_id(id)}
  def identity(%__MODULE__{host: host}), do: {:host, normalize_text(host)}

  def normalize_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> blank_to_nil()
  end

  def normalize_id(_value), do: nil

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> blank_to_nil()
  end

  defp normalize_text(value) when is_list(value), do: value |> to_string() |> normalize_text()
  defp normalize_text(_value), do: nil

  defp normalize_sources(sources) do
    [:mdns, :vendor]
    |> Enum.filter(&(&1 in List.wrap(sources)))
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
