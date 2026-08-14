defmodule Hueworks.AppSettings.HomeKitConfig do
  @moduledoc """
  Boundary module for HomeKit bridge settings.

  HomeKit entity exposure lives on lights/groups. This module owns only the
  global scene accessory toggle and bridge display name.
  """

  alias Hueworks.AppSettings.FieldParser
  alias Hueworks.Util

  @default_bridge_name "HueWorks"

  @bool_fields [:homekit_scenes_enabled]
  @string_fields [:homekit_bridge_name]

  def normalize(attrs) when is_map(attrs) do
    {attrs, errors} =
      Enum.reduce(@bool_fields, {%{}, []}, fn field, acc ->
        key = Atom.to_string(field)

        FieldParser.parse_present_field(
          acc,
          field,
          FieldParser.get_field_value(attrs, field, key),
          &FieldParser.parse_bool/1
        )
      end)
      |> then(fn {parsed_attrs, parse_errors} ->
        Enum.reduce(@string_fields, {parsed_attrs, parse_errors}, fn field, acc ->
          key = Atom.to_string(field)

          FieldParser.parse_present_field(
            acc,
            field,
            FieldParser.get_field_value(attrs, field, key),
            &FieldParser.parse_string/1
          )
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
        fallback_value(FieldParser.parse_string(config[:bridge_name] || config["bridge_name"])) ||
          @default_bridge_name
    }
  end

  def default_bridge_name, do: @default_bridge_name

  defp fallback_value({:ok, value}), do: value
end
