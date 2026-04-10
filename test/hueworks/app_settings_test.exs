defmodule Hueworks.AppSettingsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.AppSettings
  alias Hueworks.Repo
  alias Hueworks.Schemas.AppSetting

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    :ok
  end

  test "derives legacy ha_export_enabled when only room scene selectors are enabled" do
    {:ok, settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        ha_export_scenes_enabled: false,
        ha_export_room_selects_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_discovery_prefix: "homeassistant"
      })

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_room_selects_enabled == true
  end

  test "derives legacy ha_export_enabled when only light export is enabled" do
    {:ok, settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        ha_export_scenes_enabled: false,
        ha_export_room_selects_enabled: false,
        ha_export_lights_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_discovery_prefix: "homeassistant"
      })

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_room_selects_enabled == false
    assert settings.ha_export_lights_enabled == true
  end
end
