defmodule Hueworks.AppSettingsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.AppSettings
  alias Hueworks.AppSettings.HaExportConfig
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, LightState}
  alias Phoenix.PubSub

  setup do
    Repo.delete_all(AppSetting)
    :ok
  end

  test "new installations start with a comfortable manual transition" do
    settings = AppSettings.get_global()

    assert settings.default_transition_ms == 500
    assert settings.scale_transition_by_brightness == true
  end

  describe "patching the latest persisted settings" do
    setup do
      {:ok, settings} =
        AppSettings.upsert_global(%{
          latitude: 40.7128,
          longitude: -74.0060,
          timezone: "America/New_York",
          ha_export_mqtt_host: "mqtt.local"
        })

      %{settings: settings}
    end

    test "a write does not restore fields from a stale earlier read" do
      # Another writer committed after this process last read the row.
      Repo.update_all(AppSetting, set: [default_transition_ms: 1234, api_enabled: true])

      assert {:ok, settings} = AppSettings.upsert_global(%{timezone: "America/Chicago"})

      assert settings.timezone == "America/Chicago"
      assert settings.default_transition_ms == 1234
      assert settings.api_enabled == true

      persisted = Repo.get_by!(AppSetting, scope: "global")
      assert persisted.default_transition_ms == 1234
      assert persisted.api_enabled == true
    end

    test "enabling API access keeps a token persisted by another writer" do
      Repo.update_all(AppSetting, set: [api_token: String.duplicate("a", 43)])

      assert {:ok, settings} = AppSettings.enable_api_access()
      assert settings.api_token == String.duplicate("a", 43)
    end

    test "onboarding updates do not restore fields from a stale earlier read" do
      Repo.update_all(AppSetting, set: [default_transition_ms: 1234])

      assert {:ok, settings} = AppSettings.update_onboarding_state(%{onboarding_path: "direct"})
      assert settings.onboarding_path == "direct"
      assert settings.default_transition_ms == 1234
    end
  end

  describe "global timing bounds" do
    setup do
      {:ok, _settings} =
        AppSettings.upsert_global(%{
          latitude: 47.6062,
          longitude: -122.3321,
          timezone: "America/Los_Angeles"
        })

      :ok
    end

    test "all four bounds start blank" do
      settings = AppSettings.get_global()

      assert settings.min_sunrise_time == nil
      assert settings.max_sunrise_time == nil
      assert settings.min_sunset_time == nil
      assert settings.max_sunset_time == nil
    end

    test "normalizes times and treats blank as unset" do
      assert {:ok, settings} =
               AppSettings.upsert_global(%{
                 "min_sunset_time" => "18:00",
                 max_sunset_time: "20:15:30"
               })

      assert settings.min_sunset_time == "18:00:00"
      assert settings.max_sunset_time == "20:15:30"

      assert {:ok, settings} = AppSettings.upsert_global(%{min_sunset_time: ""})
      assert settings.min_sunset_time == nil
      assert settings.max_sunset_time == "20:15:30"

      assert {:ok, settings} = AppSettings.upsert_global(%{max_sunset_time: nil})
      assert settings.max_sunset_time == nil
    end

    test "midnight is stored as a real time" do
      assert {:ok, settings} = AppSettings.upsert_global(%{min_sunrise_time: "00:00"})
      assert settings.min_sunrise_time == "00:00:00"
    end

    test "equal bounds are valid" do
      assert {:ok, settings} =
               AppSettings.upsert_global(%{min_sunset_time: "18:00", max_sunset_time: "18:00"})

      assert settings.min_sunset_time == settings.max_sunset_time
    end

    test "rejects malformed values and leaves the persisted bound intact" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})

      for value <- ["25:00", "6pm", "18", 1800] do
        assert {:error, changeset} = AppSettings.upsert_global(%{min_sunset_time: value})
        assert {"must be HH:MM[:SS] or None", _opts} = changeset.errors[:min_sunset_time]
      end

      assert AppSettings.get_global().min_sunset_time == "18:00:00"
    end

    test "rejects an inverted pair instead of treating it as an overnight range" do
      assert {:error, changeset} =
               AppSettings.upsert_global(%{min_sunset_time: "20:00", max_sunset_time: "18:00"})

      assert changeset.errors[:min_sunset_time]
      assert changeset.errors[:max_sunset_time]
      assert AppSettings.get_global().min_sunset_time == nil
    end

    test "validates a one-field edit against the latest persisted pair" do
      {:ok, _settings} = AppSettings.upsert_global(%{max_sunset_time: "20:00"})

      # Another writer narrowed the pair after this process last read it.
      Repo.update_all(AppSetting, set: [max_sunset_time: "17:00:00"])

      assert {:error, changeset} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      assert changeset.errors[:min_sunset_time]
    end

    test "concurrent edits of a pair cannot leave it inverted" do
      for _round <- 1..8 do
        {:ok, _settings} =
          AppSettings.upsert_global(%{min_sunset_time: nil, max_sunset_time: nil})

        results =
          [%{min_sunset_time: "20:00"}, %{max_sunset_time: "18:00"}]
          |> Enum.map(&Task.async(fn -> AppSettings.upsert_global(&1) end))
          |> Task.await_many()

        assert Enum.count(results, &match?({:ok, _settings}, &1)) == 1

        persisted = Repo.get_by!(AppSetting, scope: "global")
        assert persisted.min_sunset_time == nil or persisted.max_sunset_time == nil
        assert AppSettings.get_global().min_sunset_time == persisted.min_sunset_time
        assert AppSettings.get_global().max_sunset_time == persisted.max_sunset_time
      end
    end

    test "concurrent edits of different fields all persist" do
      [
        %{min_sunrise_time: "06:00"},
        %{max_sunrise_time: "08:00"},
        %{min_sunset_time: "18:00"},
        %{max_sunset_time: "21:00"},
        %{default_transition_ms: 900}
      ]
      |> Enum.map(&Task.async(fn -> AppSettings.upsert_global(&1) end))
      |> Task.await_many()
      |> Enum.each(&assert({:ok, _settings} = &1))

      persisted = Repo.get_by!(AppSetting, scope: "global")

      assert persisted.min_sunrise_time == "06:00:00"
      assert persisted.max_sunrise_time == "08:00:00"
      assert persisted.min_sunset_time == "18:00:00"
      assert persisted.max_sunset_time == "21:00:00"
      assert persisted.default_transition_ms == 900
      assert AppSettings.get_global() == persisted
    end

    test "the solar config projection carries no integration credentials" do
      {:ok, _settings} =
        AppSettings.upsert_global(%{
          min_sunset_time: "18:00",
          ha_export_scenes_enabled: true,
          ha_export_mqtt_host: "mqtt.local",
          ha_export_mqtt_password: "broker-secret"
        })

      {:ok, _settings} = AppSettings.enable_api_access()
      solar_config = AppSettings.solar_config()

      assert solar_config == %{
               latitude: 47.6062,
               longitude: -122.3321,
               timezone: "America/Los_Angeles",
               min_sunrise_time: nil,
               max_sunrise_time: nil,
               min_sunset_time: "18:00:00",
               max_sunset_time: nil
             }
    end
  end

  describe "effective event order" do
    setup do
      {:ok, _settings} =
        AppSettings.upsert_global(%{
          latitude: 47.6062,
          longitude: -122.3321,
          timezone: "America/Los_Angeles"
        })

      # Valid while noon stays before 13:00; a later sunrise pushes noon past it.
      {:ok, state} =
        Scenes.create_light_state("Warm Circadian", :circadian, %{
          "override_sunset_timing" => true,
          "sunset_time" => "18:00:00",
          "brightness_sunset_offset" => -18_000
        })

      %{state: state}
    end

    test "rejects a global edit that breaks an inheriting profile and names it" do
      assert {:error, changeset} = AppSettings.upsert_global(%{min_sunrise_time: "10:00"})

      assert {message, _opts} = changeset.errors[:min_sunrise_time]
      assert message =~ "Warm Circadian"
      assert AppSettings.get_global().min_sunrise_time == nil
    end

    test "does not disable the override or change the affected profile", %{state: state} do
      config_before = Repo.get!(LightState, state.id) |> LightState.persisted_config()

      assert {:error, _changeset} = AppSettings.upsert_global(%{min_sunrise_time: "10:00"})

      assert Repo.get!(LightState, state.id) |> LightState.persisted_config() == config_before
    end

    test "an unrelated edit is not blocked by a conflict that already exists" do
      Repo.insert!(%LightState{
        name: "Already Broken",
        type: :circadian,
        config: %{
          sunrise_time: "06:00:00",
          sunset_time: "18:00:00",
          brightness_sunrise_offset: 36_000,
          brightness_sunset_offset: -36_000
        }
      })

      assert {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "17:00"})
      assert {:ok, _settings} = AppSettings.upsert_global(%{default_transition_ms: 750})
    end

    test "a fully overridden profile cannot conflict with a global edit" do
      {:ok, _state} =
        Scenes.create_light_state("Foyer Evening", :circadian, %{
          "override_sunrise_timing" => true,
          "override_sunset_timing" => true,
          "sunrise_time" => "07:00:00",
          "sunset_time" => "18:00:00",
          "brightness_sunset_offset" => -18_000
        })

      # Only Warm Circadian's name may appear, because Foyer Evening keeps local timing.
      assert {:error, changeset} = AppSettings.upsert_global(%{min_sunrise_time: "10:00"})
      {message, _opts} = changeset.errors[:min_sunrise_time]

      refute message =~ "Foyer Evening"
    end

    test "astronomical unavailability does not block a settings edit" do
      assert {:ok, settings} = AppSettings.upsert_global(%{latitude: 89.9})
      assert settings.latitude == 89.9

      assert {:ok, settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      assert settings.min_sunset_time == "18:00:00"
    end
  end

  describe "committed changes" do
    setup do
      {:ok, _settings} =
        AppSettings.upsert_global(%{
          latitude: 47.6062,
          longitude: -122.3321,
          timezone: "America/Los_Angeles"
        })

      PubSub.subscribe(Hueworks.PubSub, "domain_events")

      :ok
    end

    test "announce which fields changed without carrying their values" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})

      assert_receive {:global_settings_changed, [:min_sunset_time]}
      assert AppSettings.get_global().min_sunset_time == "18:00:00"
    end

    test "an identical write does not touch the row or announce a change" do
      {:ok, written} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      assert_receive {:global_settings_changed, [:min_sunset_time]}

      assert {:ok, repeated} = AppSettings.upsert_global(%{min_sunset_time: "18:00:00"})

      refute_receive {:global_settings_changed, _fields}, 50
      assert repeated.updated_at == written.updated_at
    end

    test "a rejected write announces nothing and keeps the persisted value" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      assert_receive {:global_settings_changed, _fields}

      assert {:error, _changeset} = AppSettings.upsert_global(%{max_sunset_time: "17:00"})

      refute_receive {:global_settings_changed, _fields}, 50
      assert AppSettings.get_global().max_sunset_time == nil
    end
  end

  describe "writers inside a surrounding transaction" do
    setup do
      {:ok, _settings} =
        AppSettings.upsert_global(%{
          latitude: 47.6062,
          longitude: -122.3321,
          timezone: "America/Los_Angeles",
          min_sunset_time: "18:00"
        })

      {:ok, _settings} = AppSettings.enable_api_access()
      PubSub.subscribe(Hueworks.PubSub, "domain_events")

      :ok
    end

    defp assert_refused_without_side_effects(writer) do
      before_write = Repo.get_by!(AppSetting, scope: "global")

      assert {:ok, {:error, :nested_settings_transaction}} = Repo.transaction(writer)

      assert Repo.get_by!(AppSetting, scope: "global") == before_write
      assert AppSettings.get_global() == before_write
      refute_receive {:global_settings_changed, _fields}, 50
    end

    test "upsert_global refuses" do
      assert_refused_without_side_effects(fn ->
        AppSettings.upsert_global(%{min_sunset_time: "19:00"})
      end)
    end

    test "enable_api_access refuses" do
      assert_refused_without_side_effects(&AppSettings.enable_api_access/0)
    end

    test "disable_api_access refuses" do
      assert_refused_without_side_effects(&AppSettings.disable_api_access/0)
    end

    test "rotate_api_token refuses" do
      assert_refused_without_side_effects(&AppSettings.rotate_api_token/0)
    end

    test "update_onboarding_state refuses" do
      assert_refused_without_side_effects(fn ->
        AppSettings.update_onboarding_state(%{onboarding_path: "direct"})
      end)
    end
  end

  describe "cyclic event order" do
    test "a sunrise bound later than a sunset bound stays valid" do
      {:ok, _state} = Scenes.create_light_state("Default Circadian", :circadian, %{})

      {:ok, _settings} =
        AppSettings.upsert_global(%{
          latitude: 47.6062,
          longitude: -122.3321,
          timezone: "America/Los_Angeles"
        })

      assert {:ok, settings} =
               AppSettings.upsert_global(%{min_sunrise_time: "19:00", max_sunset_time: "18:00"})

      assert settings.min_sunrise_time == "19:00:00"
    end
  end

  test "derives legacy ha_export_enabled when only area scene selectors are enabled" do
    {:ok, settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        ha_export_scenes_enabled: false,
        ha_export_area_selects_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_discovery_prefix: "homeassistant"
      })

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_area_selects_enabled == true
  end

  test "derives legacy ha_export_enabled when only light export is enabled" do
    {:ok, settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        ha_export_scenes_enabled: false,
        ha_export_area_selects_enabled: false,
        ha_export_lights_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_discovery_prefix: "homeassistant"
      })

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_area_selects_enabled == false
    assert settings.ha_export_lights_enabled == true
  end

  test "derives legacy ha_export_enabled from final merged partial toggle updates" do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York",
        ha_export_scenes_enabled: true,
        ha_export_area_selects_enabled: false,
        ha_export_lights_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_discovery_prefix: "homeassistant"
      })

    {:ok, settings} = AppSettings.upsert_global(%{ha_export_lights_enabled: false})

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == true
    assert settings.ha_export_area_selects_enabled == false
    assert settings.ha_export_lights_enabled == false

    {:ok, settings} =
      AppSettings.upsert_global(%{
        ha_export_scenes_enabled: false,
        ha_export_area_selects_enabled: false
      })

    assert settings.ha_export_enabled == false
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_area_selects_enabled == false
    assert settings.ha_export_lights_enabled == false

    {:ok, settings} = AppSettings.upsert_global(%{ha_export_area_selects_enabled: true})

    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == false
    assert settings.ha_export_area_selects_enabled == true
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
