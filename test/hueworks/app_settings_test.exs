defmodule Hueworks.AppSettingsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.AppSettings
  alias Hueworks.AppSettings.HaExportConfig
  alias Hueworks.Repo
  alias Hueworks.Schemas.AppSetting

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    :ok
  end

  test "new installations start with a comfortable manual transition" do
    settings = AppSettings.get_global()

    assert settings.default_transition_ms == 750
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

  test "derives legacy ha_export_enabled from final merged partial toggle updates" do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        ha_export_scenes_enabled: true,
        ha_export_room_selects_enabled: false,
        ha_export_lights_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_discovery_prefix: "homeassistant"
      })

    {:ok, settings} = AppSettings.upsert_global(%{ha_export_lights_enabled: false})

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == true
    assert settings.ha_export_room_selects_enabled == false
    assert settings.ha_export_lights_enabled == false

    {:ok, settings} =
      AppSettings.upsert_global(%{
        ha_export_scenes_enabled: false,
        ha_export_room_selects_enabled: false
      })

    assert settings.ha_export_enabled == false
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_room_selects_enabled == false
    assert settings.ha_export_lights_enabled == false

    {:ok, settings} = AppSettings.upsert_global(%{ha_export_room_selects_enabled: true})

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_room_selects_enabled == true
    assert settings.ha_export_lights_enabled == false
  end

  test "returns a changeset error for invalid solar inputs and preserves current values" do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        default_transition_ms: 900,
        scale_transition_by_brightness: true
      })

    assert {:error, changeset} =
             AppSettings.upsert_global(%{
               default_transition_ms: "fast"
             })

    assert {"must be an integer", _opts} = changeset.errors[:default_transition_ms]

    settings = AppSettings.get_global()
    assert settings.default_transition_ms == 900
    assert settings.scale_transition_by_brightness == true
  end

  test "returns a changeset error for invalid HA export inputs and preserves current values" do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        ha_export_scenes_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_mqtt_port: 1883,
        ha_export_discovery_prefix: "homeassistant"
      })

    assert {:error, changeset} =
             AppSettings.upsert_global(%{
               ha_export_mqtt_port: "eighteen eighty three"
             })

    assert {"must be an integer", _opts} = changeset.errors[:ha_export_mqtt_port]

    settings = AppSettings.get_global()
    assert settings.ha_export_mqtt_port == 1883
    assert settings.ha_export_mqtt_host == "mqtt.local"
  end

  test "HA export config treats explicitly blank password as nil for programmatic callers" do
    assert {:ok, %{ha_export_mqtt_password: nil}} =
             HaExportConfig.normalize(%{ha_export_mqtt_password: ""})
  end

  test "enabling API access generates and persists one secure token" do
    assert {:ok, enabled} = AppSettings.enable_api_access()
    assert enabled.api_enabled == true
    assert is_binary(enabled.api_token)
    assert String.length(enabled.api_token) >= 43

    assert {:ok, enabled_again} = AppSettings.enable_api_access()
    assert enabled_again.api_token == enabled.api_token
    assert AppSettings.api_enabled?() == true
  end

  test "rotating API access replaces the token and disabling keeps it unavailable" do
    {:ok, enabled} = AppSettings.enable_api_access()

    assert {:ok, rotated} = AppSettings.rotate_api_token()
    assert rotated.api_enabled == true
    refute rotated.api_token == enabled.api_token

    assert {:ok, disabled} = AppSettings.disable_api_access()
    assert disabled.api_enabled == false
    assert AppSettings.api_enabled?() == false
    assert AppSettings.api_token() == nil
  end
end
