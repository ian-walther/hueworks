defmodule Hueworks.Util do
  @moduledoc false

  def clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end

  def normalize_display_name(display_name) when is_binary(display_name) do
    display_name = String.trim(display_name)
    if display_name == "", do: nil, else: display_name
  end

  def normalize_display_name(_display_name), do: nil

  def parse_optional_integer(nil), do: nil
  def parse_optional_integer(value) when is_integer(value), do: value

  def parse_optional_integer(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      nil
    else
      case Integer.parse(value) do
        {int, ""} -> int
        _ -> nil
      end
    end
  end

  def parse_optional_integer(_value), do: nil

  def parse_optional_bool(nil), do: nil
  def parse_optional_bool(value) when value in ["true", "false"], do: value == "true"
  def parse_optional_bool(value) when is_boolean(value), do: value
  def parse_optional_bool(_value), do: nil

  def format_integer(nil), do: ""
  def format_integer(value) when is_integer(value), do: Integer.to_string(value)
  def format_integer(_value), do: ""

  def normalize_kelvin(value), do: parse_optional_integer(value)

  def normalize_host_input(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/^(host:)\s*/i, "")
  end

  def normalize_host_input(value), do: value

  def host_prefix(host) do
    host
    |> to_string()
    |> String.trim()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
  end

  def normalize_room_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
  end

  def normalize_room_name(_name), do: nil

  def normalize_room_display(name) when is_binary(name) do
    trimmed = String.trim(name)

    case String.downcase(trimmed) do
      "" -> trimmed
      downcased -> String.capitalize(downcased)
    end
  end

  def normalize_room_display(_name), do: nil

  def parse_source_filter("hue"), do: {:ok, :hue}
  def parse_source_filter("ha"), do: {:ok, :ha}
  def parse_source_filter("caseta"), do: {:ok, :caseta}
  def parse_source_filter(_), do: :error

  def parse_filter(filter) when filter in ["hue", "ha", "caseta"], do: filter
  def parse_filter(_filter), do: "all"

  def parse_room_filter(nil), do: "all"
  def parse_room_filter(""), do: "all"
  def parse_room_filter("all"), do: "all"
  def parse_room_filter("unassigned"), do: "unassigned"
  def parse_room_filter(value) when is_integer(value), do: value

  def parse_room_filter(value) when is_binary(value) do
    case Integer.parse(value) do
      {room_id, ""} -> room_id
      _ -> "all"
    end
  end

  def parse_room_filter(_value), do: "all"

  def normalize_room_filter("all", _rooms), do: "all"
  def normalize_room_filter("unassigned", _rooms), do: "unassigned"
  def normalize_room_filter(nil, _rooms), do: "all"

  def normalize_room_filter(room_id, rooms) when is_integer(room_id) do
    if Enum.any?(rooms, &(&1.id == room_id)), do: room_id, else: "all"
  end

  def normalize_room_filter(_room_id, _rooms), do: "all"

  def format_reason(reason), do: inspect(reason)

  def default_bridge_name("hue"), do: "Hue Bridge"
  def default_bridge_name("ha"), do: "Home Assistant"
  def default_bridge_name("caseta"), do: "Caseta Bridge"
  def default_bridge_name(_type), do: "Bridge"

  def format_changeset_error(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Enum.reduce(opts, message, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    if duplicate_bridge_error?(errors) do
      "Bridge with this type and host already exists."
    else
      inspect(errors)
    end
  end

  defp duplicate_bridge_error?(errors) do
    Enum.any?(errors, fn {_field, messages} ->
      Enum.any?(List.wrap(messages), &String.contains?(&1, "has already been taken"))
    end)
  end

  def parse_level(level) when is_binary(level) do
    case Integer.parse(level) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_level}
    end
  end

  def parse_level(level) when is_integer(level), do: {:ok, level}
  def parse_level(_level), do: {:error, :invalid_level}

  def parse_kelvin(kelvin) when is_binary(kelvin) do
    case Integer.parse(kelvin) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_kelvin}
    end
  end

  def parse_kelvin(kelvin) when is_integer(kelvin), do: {:ok, kelvin}
  def parse_kelvin(_kelvin), do: {:error, :invalid_kelvin}

  def to_number(value) when is_integer(value), do: value
  def to_number(value) when is_float(value), do: value

  def to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  def to_number(_value), do: nil
end
