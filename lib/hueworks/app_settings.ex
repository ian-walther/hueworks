defmodule Hueworks.AppSettings do
  @moduledoc """
  Global app settings storage with DB persistence and app-config fallback.
  """

  import Ecto.Changeset

  alias Hueworks.AppSettings.HaExportConfig
  alias Hueworks.AppSettings.HomeKitConfig
  alias Hueworks.AppSettings.SolarConfig
  alias Hueworks.Repo
  alias Hueworks.Schemas.AppSetting
  alias HueworksApp.Cache

  @global_scope "global"
  @cache_namespace :app_settings
  @cache_key :global

  def get_global do
    Cache.get_or_load(@cache_namespace, @cache_key, &load_global/0)
  end

  def upsert_global(attrs) when is_map(attrs) do
    current = get_global()
    base_attrs = merged_attrs(current)

    case normalize_updates(attrs) do
      {:ok, updates} ->
        merged =
          base_attrs
          |> Map.merge(updates)
          |> Map.put(:scope, @global_scope)
          |> HaExportConfig.finalize_enabled(attrs)

        result =
          case Repo.get_by(AppSetting, scope: @global_scope) do
            nil ->
              %AppSetting{}
              |> AppSetting.global_changeset(merged)
              |> Repo.insert()

            %AppSetting{} = app_setting ->
              app_setting
              |> AppSetting.global_changeset(merged)
              |> Repo.update()
          end

        case result do
          {:ok, %AppSetting{} = app_setting} ->
            :ok = Cache.put(@cache_namespace, @cache_key, app_setting)
            {:ok, app_setting}

          other ->
            other
        end

      {:error, errors} ->
        {:error, boundary_error_changeset(current, base_attrs, errors)}
    end
  end

  def global_map do
    app_setting = get_global()

    %{
      latitude: app_setting.latitude,
      longitude: app_setting.longitude,
      timezone: app_setting.timezone,
      default_transition_ms: app_setting.default_transition_ms || 750,
      scale_transition_by_brightness: app_setting.scale_transition_by_brightness == true,
      ha_export_enabled: app_setting.ha_export_enabled == true,
      ha_export_scenes_enabled: app_setting.ha_export_scenes_enabled == true,
      ha_export_area_selects_enabled: app_setting.ha_export_area_selects_enabled == true,
      ha_export_lights_enabled: app_setting.ha_export_lights_enabled == true,
      ha_export_mqtt_host: app_setting.ha_export_mqtt_host,
      ha_export_mqtt_port: app_setting.ha_export_mqtt_port || 1883,
      ha_export_mqtt_username: app_setting.ha_export_mqtt_username,
      ha_export_mqtt_password: app_setting.ha_export_mqtt_password,
      ha_export_discovery_prefix: app_setting.ha_export_discovery_prefix || "homeassistant",
      homekit_scenes_enabled: app_setting.homekit_scenes_enabled == true,
      homekit_bridge_name: app_setting.homekit_bridge_name || HomeKitConfig.default_bridge_name(),
      api_enabled: api_enabled?(app_setting)
    }
  end

  def api_enabled? do
    get_global()
    |> api_enabled?()
  end

  def api_token do
    app_setting = get_global()

    if api_enabled?(app_setting), do: app_setting.api_token, else: nil
  end

  def enable_api_access do
    app_setting = get_global()

    update_api_access(%{
      api_enabled: true,
      api_token: app_setting.api_token || generate_api_token()
    })
  end

  def disable_api_access do
    update_api_access(%{api_enabled: false})
  end

  def rotate_api_token do
    if api_enabled?() do
      update_api_access(%{api_token: generate_api_token()})
    else
      {:error, :api_disabled}
    end
  end

  defp load_global do
    case Repo.get_by(AppSetting, scope: @global_scope) do
      %AppSetting{} = app_setting -> app_setting
      nil -> fallback_setting()
    end
  end

  defp fallback_setting do
    solar = SolarConfig.fallback_attrs()
    ha = HaExportConfig.fallback_attrs()
    homekit = HomeKitConfig.fallback_attrs()

    struct(
      AppSetting,
      solar |> Map.merge(ha) |> Map.merge(homekit) |> Map.put(:scope, @global_scope)
    )
  end

  defp normalize_updates(attrs) do
    [
      SolarConfig.normalize(attrs),
      HaExportConfig.normalize(attrs),
      HomeKitConfig.normalize(attrs)
    ]
    |> Enum.reduce({%{}, []}, fn
      {:ok, update}, {acc, errors} ->
        {Map.merge(acc, update), errors}

      {:error, new_errors}, {acc, errors} ->
        {acc, errors ++ new_errors}
    end)
    |> case do
      {updates, []} -> {:ok, updates}
      {_updates, errors} -> {:error, errors}
    end
  end

  defp boundary_error_changeset(current, base_attrs, errors) do
    current
    |> change(base_attrs)
    |> Map.put(:action, :validate)
    |> then(fn changeset ->
      Enum.reduce(errors, changeset, fn {field, message}, acc ->
        case existing_field(field) do
          nil -> add_error(acc, :scope, "#{field} #{message}")
          atom_field -> add_error(acc, atom_field, message)
        end
      end)
    end)
  end

  defp existing_field(field) when is_atom(field), do: field

  defp existing_field(field) when is_binary(field) do
    try do
      String.to_existing_atom(field)
    rescue
      ArgumentError -> nil
    end
  end

  defp existing_field(_field), do: nil

  defp merged_attrs(%AppSetting{} = current) do
    current
    |> solar_attrs_from_setting()
    |> Map.merge(ha_attrs_from_setting(current))
  end

  defp solar_attrs_from_setting(%AppSetting{} = s) do
    %{
      latitude: s.latitude,
      longitude: s.longitude,
      timezone: s.timezone,
      default_transition_ms: s.default_transition_ms || 750,
      scale_transition_by_brightness: s.scale_transition_by_brightness == true
    }
  end

  defp ha_attrs_from_setting(%AppSetting{} = s) do
    %{
      ha_export_enabled: s.ha_export_enabled == true,
      ha_export_scenes_enabled: s.ha_export_scenes_enabled == true,
      ha_export_area_selects_enabled: s.ha_export_area_selects_enabled == true,
      ha_export_lights_enabled: s.ha_export_lights_enabled == true,
      ha_export_mqtt_host: s.ha_export_mqtt_host,
      ha_export_mqtt_port: s.ha_export_mqtt_port || 1883,
      ha_export_mqtt_username: s.ha_export_mqtt_username,
      ha_export_mqtt_password: s.ha_export_mqtt_password,
      ha_export_discovery_prefix: s.ha_export_discovery_prefix || "homeassistant",
      homekit_scenes_enabled: s.homekit_scenes_enabled == true,
      homekit_bridge_name: s.homekit_bridge_name || HomeKitConfig.default_bridge_name(),
      api_enabled: s.api_enabled == true,
      api_token: s.api_token
    }
  end

  defp update_api_access(attrs) do
    result =
      case Repo.get_by(AppSetting, scope: @global_scope) do
        nil ->
          %AppSetting{}
          |> AppSetting.changeset(Map.put(attrs, :scope, @global_scope))
          |> Repo.insert()

        %AppSetting{} = app_setting ->
          app_setting
          |> AppSetting.changeset(attrs)
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

  defp api_enabled?(%AppSetting{api_enabled: true, api_token: token})
       when is_binary(token) and token != "",
       do: true

  defp api_enabled?(_app_setting), do: false

  defp generate_api_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
