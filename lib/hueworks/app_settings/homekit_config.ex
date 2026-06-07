defmodule Hueworks.AppSettings.HomeKitConfig do
  @moduledoc """
  Boundary module for HomeKit bridge settings.

  HomeKit entity exposure lives on lights/groups. This module owns only the
  global scene accessory toggle and bridge display name.
  """

  alias Hueworks.Util

  @default_bridge_name "HueWorks"

  @bool_fields [:homekit_scenes_enabled]
  @string_fields [:homekit_bridge_name]

  def normalize(attrs) when is_map(attrs) do
    {attrs, errors} =
      Enum.reduce(@bool_fields, {%{}, []}, fn field, acc ->
        key = Atom.to_string(field)
        parse_present_field(acc, field, get_field_value(attrs, field, key), &parse_bool/1)
      end)
      |> then(fn {parsed_attrs, parse_errors} ->
        Enum.reduce(@string_fields, {parsed_attrs, parse_errors}, fn field, acc ->
          key = Atom.to_string(field)
          parse_present_field(acc, field, get_field_value(attrs, field, key), &parse_string/1)
        end)
      end)

    case errors do
      [] -> {:ok, attrs}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def normalize(_), do: {:error, [{"homekit_config", "must be a map"}]}

  def fallback_attrs do
    config = Application.get_env(:hueworks, :homekit, %{})

    %{
      homekit_scenes_enabled:
        Util.parse_optional_bool(config[:scenes_enabled] || config["scenes_enabled"]) == true,
      homekit_bridge_name:
        fallback_value(parse_string(config[:bridge_name] || config["bridge_name"])) ||
          @default_bridge_name
    }
  end

  def default_bridge_name, do: @default_bridge_name

  defp get_field_value(attrs, atom_key, string_key) do
    cond do
      Map.has_key?(attrs, atom_key) -> Map.get(attrs, atom_key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> :missing
    end
  end

  defp parse_present_field({attrs, errors}, _key, :missing, _parse_fn), do: {attrs, errors}

  defp parse_present_field({attrs, errors}, key, value, parse_fn) do
    case parse_fn.(value) do
      {:ok, parsed} -> {Map.put(attrs, key, parsed), errors}
      {:error, message} -> {attrs, [{Atom.to_string(key), message} | errors]}
    end
  end

  defp parse_bool(nil), do: {:ok, nil}

  defp parse_bool(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      case Util.parse_optional_bool(value) do
        nil -> {:error, "must be true or false"}
        parsed -> {:ok, parsed}
      end
    end
  end

  defp parse_bool(value) when is_boolean(value), do: {:ok, value}
  defp parse_bool(_), do: {:error, "must be true or false"}

  defp parse_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      {:ok, trimmed}
    end
  end

  defp parse_string(nil), do: {:ok, nil}
  defp parse_string(_), do: {:error, "must be a string"}

  defp fallback_value({:ok, value}), do: value
end
