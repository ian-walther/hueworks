defmodule Hueworks.Import.NormalizeJson do
  @moduledoc false

  def to_map(value) when is_map(value) do
    value
    |> Enum.map(fn {key, val} ->
      {normalize_key(key), normalize_value(val)}
    end)
    |> Map.new()
  end

  def to_map(value) when is_list(value) do
    Enum.map(value, &normalize_value/1)
  end

  def to_map(value), do: normalize_value(value)

  defp normalize_value(value) when is_map(value), do: to_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)
end
