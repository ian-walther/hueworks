defmodule Hueworks.AppSettings do
  @moduledoc """
  Global app settings storage with DB persistence and app-config fallback.
  """

  alias Hueworks.Repo
  alias Hueworks.Schemas.AppSetting
  alias HueworksApp.Cache

  @global_scope "global"
  @config_key :global_solar_config
  @cache_namespace :app_settings
  @cache_key :global

  def get_global do
    Cache.get_or_load(@cache_namespace, @cache_key, &load_global/0)
  end

  def upsert_global(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_attrs()
      |> with_defaults_from_current()
      |> with_derived_ha_export_enabled()
      |> Map.put(:scope, @global_scope)

    result =
      case Repo.get_by(AppSetting, scope: @global_scope) do
        nil ->
          %AppSetting{}
          |> AppSetting.global_changeset(attrs)
          |> Repo.insert()

        %AppSetting{} = app_setting ->
          app_setting
          |> AppSetting.global_changeset(attrs)
          |> Repo.update()
      end

    case result do
      {:ok, %AppSetting{} = app_setting} ->
        :ok = Cache.put(@cache_namespace, @cache_key, app_setting)
        {:ok, app_setting}

      other ->
        other
    end
  end

  def global_map do
    app_setting = get_global()

    %{
      latitude: app_setting.latitude,
      longitude: app_setting.longitude,
      timezone: app_setting.timezone,
      default_transition_ms: app_setting.default_transition_ms || 0,
      scale_transition_by_brightness: app_setting.scale_transition_by_brightness == true,
      ha_export_enabled: app_setting.ha_export_enabled == true,
      ha_export_scenes_enabled: app_setting.ha_export_scenes_enabled == true,
      ha_export_room_selects_enabled: app_setting.ha_export_room_selects_enabled == true,
      ha_export_mqtt_host: app_setting.ha_export_mqtt_host,
      ha_export_mqtt_port: app_setting.ha_export_mqtt_port || 1883,
      ha_export_mqtt_username: app_setting.ha_export_mqtt_username,
      ha_export_mqtt_password: app_setting.ha_export_mqtt_password,
      ha_export_discovery_prefix: app_setting.ha_export_discovery_prefix || "homeassistant"
    }
  end

  defp with_defaults_from_current(attrs) do
    current = get_global()

    current_attrs = %{
      latitude: current.latitude,
      longitude: current.longitude,
      timezone: current.timezone,
      default_transition_ms: current.default_transition_ms || 0,
      scale_transition_by_brightness: current.scale_transition_by_brightness == true,
      ha_export_enabled: current.ha_export_enabled == true,
      ha_export_scenes_enabled: current.ha_export_scenes_enabled == true,
      ha_export_room_selects_enabled: current.ha_export_room_selects_enabled == true,
      ha_export_mqtt_host: current.ha_export_mqtt_host,
      ha_export_mqtt_port: current.ha_export_mqtt_port || 1883,
      ha_export_mqtt_username: current.ha_export_mqtt_username,
      ha_export_mqtt_password: current.ha_export_mqtt_password,
      ha_export_discovery_prefix: current.ha_export_discovery_prefix || "homeassistant"
    }

    Map.merge(current_attrs, attrs)
  end

  defp fallback_setting do
    config = Application.get_env(:hueworks, @config_key, %{})
    ha_export_config = Application.get_env(:hueworks, :ha_export_mqtt, %{})

    %AppSetting{
      scope: @global_scope,
      latitude: parse_number(config[:latitude] || config["latitude"]),
      longitude: parse_number(config[:longitude] || config["longitude"]),
      timezone: parse_timezone(config[:timezone] || config["timezone"]),
      default_transition_ms: Application.get_env(:hueworks, :default_transition_ms, 0),
      scale_transition_by_brightness:
        Application.get_env(:hueworks, :scale_transition_by_brightness, false) == true,
      ha_export_enabled:
        parse_boolean(ha_export_config[:enabled] || ha_export_config["enabled"]) == true,
      ha_export_scenes_enabled:
        parse_boolean(ha_export_config[:enabled] || ha_export_config["enabled"]) == true,
      ha_export_room_selects_enabled:
        parse_boolean(ha_export_config[:enabled] || ha_export_config["enabled"]) == true,
      ha_export_mqtt_host: parse_string(ha_export_config[:host] || ha_export_config["host"]),
      ha_export_mqtt_port:
        parse_port(ha_export_config[:port] || ha_export_config["port"]) || 1883,
      ha_export_mqtt_username:
        parse_string(ha_export_config[:username] || ha_export_config["username"]),
      ha_export_mqtt_password:
        parse_string(ha_export_config[:password] || ha_export_config["password"]),
      ha_export_discovery_prefix:
        parse_string(ha_export_config[:discovery_prefix] || ha_export_config["discovery_prefix"]) ||
          "homeassistant"
    }
  end

  defp load_global do
    case Repo.get_by(AppSetting, scope: @global_scope) do
      %AppSetting{} = app_setting -> app_setting
      nil -> fallback_setting()
    end
  end

  defp normalize_attrs(attrs) do
    %{
      latitude: parse_number(Map.get(attrs, :latitude) || Map.get(attrs, "latitude")),
      longitude: parse_number(Map.get(attrs, :longitude) || Map.get(attrs, "longitude")),
      timezone: parse_timezone(Map.get(attrs, :timezone) || Map.get(attrs, "timezone")),
      default_transition_ms:
        parse_transition_ms(
          Map.get(attrs, :default_transition_ms) || Map.get(attrs, "default_transition_ms")
        ),
      scale_transition_by_brightness:
        parse_boolean(
          attr_value(attrs, :scale_transition_by_brightness, "scale_transition_by_brightness")
        ),
      ha_export_enabled:
        parse_boolean(attr_value(attrs, :ha_export_enabled, "ha_export_enabled")),
      ha_export_scenes_enabled:
        parse_boolean(attr_value(attrs, :ha_export_scenes_enabled, "ha_export_scenes_enabled")),
      ha_export_room_selects_enabled:
        parse_boolean(
          attr_value(
            attrs,
            :ha_export_room_selects_enabled,
            "ha_export_room_selects_enabled"
          )
        ),
      ha_export_mqtt_host:
        parse_string(attr_value(attrs, :ha_export_mqtt_host, "ha_export_mqtt_host")),
      ha_export_mqtt_port:
        parse_port(attr_value(attrs, :ha_export_mqtt_port, "ha_export_mqtt_port")),
      ha_export_mqtt_username:
        parse_string(attr_value(attrs, :ha_export_mqtt_username, "ha_export_mqtt_username")),
      ha_export_mqtt_password:
        parse_string(attr_value(attrs, :ha_export_mqtt_password, "ha_export_mqtt_password")),
      ha_export_discovery_prefix:
        parse_string(attr_value(attrs, :ha_export_discovery_prefix, "ha_export_discovery_prefix"))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> with_derived_ha_export_enabled()
  end

  defp with_derived_ha_export_enabled(attrs) when is_map(attrs) do
    has_new_toggles =
      Map.has_key?(attrs, :ha_export_scenes_enabled) or
        Map.has_key?(attrs, :ha_export_room_selects_enabled)

    if has_new_toggles do
      combined =
        Map.get(attrs, :ha_export_scenes_enabled) == true or
          Map.get(attrs, :ha_export_room_selects_enabled) == true

      Map.put(attrs, :ha_export_enabled, combined)
    else
      attrs
    end
  end

  defp attr_value(attrs, atom_key, string_key) do
    cond do
      Map.has_key?(attrs, atom_key) -> Map.get(attrs, atom_key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> nil
    end
  end

  defp parse_number(value) when is_integer(value), do: value * 1.0
  defp parse_number(value) when is_float(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp parse_number(_value), do: nil

  defp parse_timezone(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_timezone(_value), do: nil

  defp parse_transition_ms(value) when is_integer(value) and value >= 0, do: value

  defp parse_transition_ms(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      true ->
        case Integer.parse(trimmed) do
          {number, ""} when number >= 0 -> number
          _ -> nil
        end
    end
  end

  defp parse_transition_ms(_value), do: nil

  defp parse_port(value) when is_integer(value) and value >= 1 and value <= 65_535, do: value

  defp parse_port(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      true ->
        case Integer.parse(trimmed) do
          {number, ""} when number >= 1 and number <= 65_535 -> number
          _ -> nil
        end
    end
  end

  defp parse_port(_value), do: nil

  defp parse_boolean(value) when value in [true, false], do: value

  defp parse_boolean(value) when is_binary(value) do
    case String.trim(String.downcase(value)) do
      "true" -> true
      "false" -> false
      "" -> nil
      _ -> nil
    end
  end

  defp parse_boolean(_value), do: nil

  defp parse_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_string(_value), do: nil
end
