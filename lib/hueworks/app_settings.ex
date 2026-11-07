defmodule Hueworks.AppSettings do
  @moduledoc """
  Global app settings storage with DB persistence and app-config fallback.

  Reads come straight from the database, so nobody sees an uncommitted write.
  Every writer patches the latest persisted row in its own immediate transaction
  and announces the change after that commit. Writers refuse to run inside a
  surrounding transaction, which could still roll back after the announcement.
  """

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Hueworks.AppSettings.HaExportConfig
  alias Hueworks.AppSettings.HomeKitConfig
  alias Hueworks.AppSettings.SolarConfig
  alias Hueworks.Circadian
  alias Hueworks.Circadian.Timing
  alias Hueworks.DomainEvents
  alias Hueworks.Repo
  alias Hueworks.Schemas.{AppSetting, LightState}
  alias Hueworks.Util

  @global_scope "global"
  @location_fields [:latitude, :longitude, :timezone]

  def get_global do
    case Repo.get_by(AppSetting, scope: @global_scope) do
      %AppSetting{} = app_setting -> app_setting
      nil -> fallback_setting()
    end
  end

  def default_transition_ms, do: SolarConfig.default_transition_ms()

  def default_scale_transition_by_brightness?,
    do: SolarConfig.default_scale_transition_by_brightness?()

  def upsert_global(attrs) when is_map(attrs) do
    case normalize_updates(attrs) do
      {:ok, updates} ->
        patch_global(fn current ->
          current
          |> AppSetting.global_changeset(updates)
          |> HaExportConfig.finalize_enabled(attrs)
        end)

      {:error, errors} ->
        {:error, boundary_error_changeset(get_global(), errors)}
    end
  end

  @doc """
  The settings a circadian calculation needs, without integration credentials.
  """
  def solar_config, do: solar_config(get_global())

  def solar_config(%AppSetting{} = app_setting) do
    Map.take(app_setting, @location_fields ++ Timing.window_fields())
  end

  def global_map do
    app_setting = get_global()

    %{
      latitude: app_setting.latitude,
      longitude: app_setting.longitude,
      timezone: app_setting.timezone,
      default_transition_ms: app_setting.default_transition_ms || default_transition_ms(),
      scale_transition_by_brightness:
        transition_scaling_value(app_setting.scale_transition_by_brightness),
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
    patch_global(fn current ->
      AppSetting.changeset(current, %{
        api_enabled: true,
        api_token: current.api_token || generate_api_token()
      })
    end)
  end

  def disable_api_access do
    patch_global(&AppSetting.changeset(&1, %{api_enabled: false}))
  end

  def rotate_api_token do
    patch_global(fn current ->
      if api_enabled?(current) do
        AppSetting.changeset(current, %{api_token: generate_api_token()})
      else
        {:error, :api_disabled}
      end
    end)
  end

  def update_onboarding_state(attrs) when is_map(attrs) do
    patch_global(&AppSetting.changeset(&1, attrs))
  end

  defp patch_global(build_changeset) do
    if Repo.in_transaction?() do
      {:error, :nested_settings_transaction}
    else
      commit_patch(build_changeset)
    end
  end

  defp commit_patch(build_changeset) do
    with {:ok, {app_setting, changed_fields}} <-
           Repo.transaction(fn -> write_patch(build_changeset) end, mode: :immediate) do
      announce_changes(changed_fields)
      {:ok, app_setting}
    end
  end

  defp write_patch(build_changeset) do
    current = get_global()

    with %Ecto.Changeset{} = changeset <- build_changeset.(current),
         changeset = validate_event_order(changeset, current),
         {:ok, app_setting} <- Repo.insert_or_update(changeset) do
      {app_setting, Map.keys(changeset.changes)}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp announce_changes([]), do: :ok
  defp announce_changes(fields), do: DomainEvents.global_settings_changed(fields)

  # Location and global window edits move effective events for every profile
  # that uses them. Only a conflict this edit introduces blocks it; failing to
  # calculate an event is seasonal and leaves the edit valid.
  defp validate_event_order(%Ecto.Changeset{valid?: false} = changeset, _current), do: changeset

  defp validate_event_order(changeset, current) do
    (Timing.window_fields() ++ @location_fields)
    |> Enum.find(&Map.has_key?(changeset.changes, &1))
    |> case do
      nil -> changeset
      field -> add_event_order_conflicts(changeset, field, current)
    end
  end

  defp add_event_order_conflicts(changeset, field, current) do
    current
    |> solar_config()
    |> event_order_conflicts(solar_config(apply_changes(changeset)))
    |> case do
      [] ->
        changeset

      names ->
        add_error(
          changeset,
          field,
          "would put sunrise and sunset out of order for: #{Enum.join(names, ", ")}"
        )
    end
  end

  defp event_order_conflicts(previous, next) do
    case Circadian.local_today(next) do
      {:ok, date} ->
        from(ls in LightState,
          where: ls.type == :circadian,
          order_by: [asc: ls.name, asc: ls.id]
        )
        |> Repo.all()
        |> Enum.filter(fn light_state ->
          config = LightState.circadian_config(light_state)

          Circadian.invalid_event_order?(config, next, date) and
            not Circadian.invalid_event_order?(config, previous, date)
        end)
        |> Enum.map(& &1.name)

      {:error, _reason} ->
        []
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

  defp boundary_error_changeset(current, errors) do
    current
    |> change()
    |> Map.put(:action, :validate)
    |> then(fn changeset ->
      Enum.reduce(errors, changeset, fn {field, message}, acc ->
        case Util.existing_atom(field) do
          nil -> add_error(acc, :scope, "#{field} #{message}")
          atom_field -> add_error(acc, atom_field, message)
        end
      end)
    end)
  end

  defp api_enabled?(%AppSetting{api_enabled: true, api_token: token})
       when is_binary(token) and token != "",
       do: true

  defp api_enabled?(_app_setting), do: false

  defp transition_scaling_value(value) when is_boolean(value), do: value
  defp transition_scaling_value(_value), do: default_scale_transition_by_brightness?()

  defp generate_api_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
