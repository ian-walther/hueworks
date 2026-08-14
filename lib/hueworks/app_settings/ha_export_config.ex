defmodule Hueworks.AppSettings.HaExportConfig do
  @moduledoc """
  Boundary module for Home Assistant export settings.

  Owns parsing, normalization, and the rule that ha_export_enabled is derived
  from the three sub-toggles (scenes, area selects, lights).

  Does not validate ranges — that is AppSetting.global_changeset's job.
  Does not change the persisted shape — these remain flat columns on AppSetting.
  """

  alias Hueworks.AppSettings.FieldParser
  alias Hueworks.Util

  @toggle_fields [
    :ha_export_scenes_enabled,
    :ha_export_area_selects_enabled,
    :ha_export_lights_enabled
  ]

  @bool_fields [
    :ha_export_enabled,
    :ha_export_scenes_enabled,
    :ha_export_area_selects_enabled,
    :ha_export_lights_enabled
  ]

  @string_fields [
    :ha_export_mqtt_host,
    :ha_export_mqtt_username,
    :ha_export_mqtt_password,
    :ha_export_discovery_prefix
  ]

  @doc """
  Normalizes a mixed-key attrs map to an atom-keyed map suitable for
  AppSetting.global_changeset. Derives ha_export_enabled from sub-toggles
  when any sub-toggle is present. Missing fields are omitted, explicitly blank
  fields are preserved as nil, and invalid present fields return errors.
  """
  def normalize(attrs) when is_map(attrs) do
    case parse_attrs(attrs) do
      {:ok, parsed_attrs} -> {:ok, derive_enabled(parsed_attrs)}
      {:error, _errors} = error -> error
    end
  end

  def normalize(_), do: {:error, [{"ha_export_config", "must be a map"}]}

  @doc """
  Builds a fallback attrs map from Application config (no DB row present).
  """
  def fallback_attrs do
    config = Application.get_env(:hueworks, :ha_export_mqtt, %{})
    enabled = Util.parse_optional_bool(config[:enabled] || config["enabled"]) == true

    %{
      ha_export_enabled: enabled,
      ha_export_scenes_enabled: enabled,
      ha_export_area_selects_enabled: enabled,
      ha_export_lights_enabled: false,
      ha_export_mqtt_host:
        fallback_value(FieldParser.parse_string(config[:host] || config["host"])),
      ha_export_mqtt_port: fallback_value(parse_port(config[:port] || config["port"])) || 1883,
      ha_export_mqtt_username:
        fallback_value(FieldParser.parse_string(config[:username] || config["username"])),
      ha_export_mqtt_password:
        fallback_value(FieldParser.parse_string(config[:password] || config["password"])),
      ha_export_discovery_prefix:
        fallback_value(
          FieldParser.parse_string(config[:discovery_prefix] || config["discovery_prefix"])
        ) ||
          "homeassistant"
    }
  end

  defp parse_attrs(attrs) do
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
      |> FieldParser.parse_present_field(
        :ha_export_mqtt_port,
        FieldParser.get_field_value(attrs, :ha_export_mqtt_port, "ha_export_mqtt_port"),
        &parse_port/1
      )

    case errors do
      [] -> {:ok, attrs}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp derive_enabled(attrs) do
    has_toggles = Enum.any?(@toggle_fields, &Map.has_key?(attrs, &1))

    if has_toggles do
      combined = Enum.any?(@toggle_fields, &(Map.get(attrs, &1) == true))
      Map.put(attrs, :ha_export_enabled, combined)
    else
      attrs
    end
  end

  def finalize_enabled(attrs, incoming_attrs) when is_map(attrs) and is_map(incoming_attrs) do
    if toggle_present?(incoming_attrs) do
      Map.put(attrs, :ha_export_enabled, Enum.any?(@toggle_fields, &(Map.get(attrs, &1) == true)))
    else
      attrs
    end
  end

  def finalize_enabled(attrs, _incoming_attrs), do: attrs

  defp toggle_present?(attrs) do
    Enum.any?(@toggle_fields, fn field ->
      Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field))
    end)
  end

  defp parse_port(nil), do: {:ok, nil}

  defp parse_port(value) when is_integer(value) and value >= 1 and value <= 65_535,
    do: {:ok, value}

  defp parse_port(value) when is_integer(value), do: {:error, "must be between 1 and 65535"}

  defp parse_port(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      case Integer.parse(value) do
        {n, ""} when n >= 1 and n <= 65_535 -> {:ok, n}
        {_, ""} -> {:error, "must be between 1 and 65535"}
        _ -> {:error, "must be an integer"}
      end
    end
  end

  defp parse_port(_), do: {:error, "must be an integer"}

  defp fallback_value({:ok, value}), do: value
end
