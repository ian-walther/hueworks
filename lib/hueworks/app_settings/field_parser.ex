defmodule Hueworks.AppSettings.FieldParser do
  @moduledoc false

  alias Hueworks.Util

  def get_field_value(attrs, atom_key, string_key) do
    cond do
      Map.has_key?(attrs, atom_key) -> Map.get(attrs, atom_key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> :missing
    end
  end

  def parse_present_field({attrs, errors}, _key, :missing, _parse_fn), do: {attrs, errors}

  def parse_present_field({attrs, errors}, key, value, parse_fn) do
    case parse_fn.(value) do
      {:ok, parsed} -> {Map.put(attrs, key, parsed), errors}
      {:error, message} -> {attrs, [{Atom.to_string(key), message} | errors]}
    end
  end

  def parse_string(value) when is_binary(value), do: {:ok, Util.blank_to_nil(value)}
  def parse_string(nil), do: {:ok, nil}
  def parse_string(_value), do: {:error, "must be a string"}

  def parse_bool(nil), do: {:ok, nil}

  def parse_bool(value) when is_binary(value) do
    case Util.blank_to_nil(value) do
      nil -> {:ok, nil}
      value -> parse_bool_value(value)
    end
  end

  def parse_bool(value) when is_boolean(value), do: {:ok, value}
  def parse_bool(_value), do: {:error, "must be true or false"}

  def parse_number(nil), do: {:ok, nil}

  def parse_number(value) when is_binary(value) do
    case Util.blank_to_nil(value) do
      nil -> {:ok, nil}
      value -> parse_number_value(value)
    end
  end

  def parse_number(value) when is_integer(value) or is_float(value), do: {:ok, value}
  def parse_number(_value), do: {:error, "must be a number"}

  def parse_non_negative_integer(nil), do: {:ok, nil}

  def parse_non_negative_integer(value) when is_integer(value) and value >= 0,
    do: {:ok, value}

  def parse_non_negative_integer(value) when is_integer(value), do: {:error, "must be >= 0"}

  def parse_non_negative_integer(value) when is_binary(value) do
    case Util.blank_to_nil(value) do
      nil -> {:ok, nil}
      value -> parse_non_negative_integer_value(value)
    end
  end

  def parse_non_negative_integer(_value), do: {:error, "must be an integer"}

  defp parse_bool_value(value) do
    case Util.parse_optional_bool(value) do
      nil -> {:error, "must be true or false"}
      parsed -> {:ok, parsed}
    end
  end

  defp parse_number_value(value) do
    case Util.to_number(value) do
      nil -> {:error, "must be a number"}
      number -> {:ok, number}
    end
  end

  defp parse_non_negative_integer_value(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, number}
      {_, ""} -> {:error, "must be >= 0"}
      _ -> {:error, "must be an integer"}
    end
  end
end
