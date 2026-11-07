defmodule HueworksWeb.LightStateEditorTimingTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.AppSettings
  alias Hueworks.Circadian
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, LightState}

  @sunrise_fields ~w(sunrise_time min_sunrise_time max_sunrise_time sunrise_offset brightness_sunrise_offset temperature_sunrise_offset)
  @sunset_fields ~w(sunset_time min_sunset_time max_sunset_time sunset_offset brightness_sunset_offset temperature_sunset_offset)
  @ramp_fields ~w(brightness_mode_time_dark brightness_mode_time_light)

  @stored_sunset %{
    "sunset_time" => "17:30:00",
    "min_sunset_time" => "17:00:00",
    "max_sunset_time" => "17:45:00",
    "sunset_offset" => 300,
    "brightness_sunset_offset" => 120,
    "temperature_sunset_offset" => -120,
    "brightness_mode_time_dark" => 1800,
    "brightness_mode_time_light" => 7200
  }

  setup do
    Repo.delete_all(AppSetting)

    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 47.6062,
        longitude: -122.3321,
        timezone: "America/Los_Angeles"
      })

    :ok
  end

  defp input(field), do: "#light-state-#{field}"

  defp assert_locked(view, fields) do
    for field <- fields do
      assert has_element?(view, "#{input(field)}[disabled]"), "expected #{field} to be locked"
    end
  end

  defp assert_editable(view, fields) do
    for field <- fields do
      assert has_element?(view, "#{input(field)}:not([disabled])"),
             "expected #{field} to be editable"
    end
  end

  defp set_override(view, sunrise, sunset) do
    render_change(view, "update_form", %{
      "override_sunrise_timing" => to_string(sunrise),
      "override_sunset_timing" => to_string(sunset)
    })
  end

  defp persisted(id) do
    LightState
    |> Repo.get!(id)
    |> LightState.persisted_config()
  end

  defp assigns_of(view), do: :sys.get_state(view.pid).socket.assigns

  defp stored_profile(flags \\ %{"override_sunset_timing" => false}) do
    {:ok, state} =
      Scenes.create_light_state("Default Circadian", :circadian, Map.merge(@stored_sunset, flags))

    state
  end

  describe "a new profile" do
    test "inherits both events with their timing controls locked", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/config/light-states/new/circadian")

      refute has_element?(view, "#light-state-override_sunrise_timing[checked]")
      refute has_element?(view, "#light-state-override_sunset_timing[checked]")

      assert_locked(view, @sunrise_fields ++ @sunset_fields ++ @ramp_fields)
      assert_editable(view, ~w(min_brightness max_brightness min_color_temp max_color_temp))
      assert has_element?(view, "#light-state-brightness-mode:not([disabled])")
    end

    test "saves explicit inheritance without copying global bounds", %{conn: conn} do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      {:ok, view, _html} = live(conn, "/config/light-states/new/circadian")

      assert has_element?(view, "#{input("min_sunset_time")}[value='18:00:00']")

      render_submit(view, "save", %{"name" => "Fresh", "save_action" => "save"})

      config = Repo.get_by!(LightState, name: "Fresh") |> LightState.persisted_config()

      assert config["override_sunrise_timing"] == false
      assert config["override_sunset_timing"] == false
      refute Map.has_key?(config, "min_sunset_time")
    end

    test "enabling override reveals blank local bounds, not the global ones", %{conn: conn} do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      {:ok, view, _html} = live(conn, "/config/light-states/new/circadian")

      set_override(view, false, true)

      assert_editable(view, @sunset_fields)
      refute has_element?(view, "#{input("min_sunset_time")}[value='18:00:00']")

      render_submit(view, "save", %{"name" => "Blank Local", "save_action" => "save"})

      config = Repo.get_by!(LightState, name: "Blank Local") |> LightState.persisted_config()

      assert config["override_sunset_timing"] == true
      assert config["min_sunset_time"] == nil
    end
  end

  describe "an inherited event" do
    test "displays effective values while its stored values stay stored", %{conn: conn} do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      state = stored_profile()

      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      assert_locked(view, @sunset_fields)
      assert has_element?(view, "#{input("sunset_time")}[value='']")
      assert has_element?(view, "#{input("min_sunset_time")}[value='18:00:00']")
      assert has_element?(view, "#{input("max_sunset_time")}[value='']")
      assert has_element?(view, "#{input("sunset_offset")}[value='0']")
      assert has_element?(view, "#{input("brightness_sunset_offset")}[value='0']")
      assert has_element?(view, "#{input("temperature_sunset_offset")}[value='0']")
      assert has_element?(view, "#light-state-sunset-timing-note", "a global minimum of 18:00:00")

      assert Map.take(persisted(state.id), Map.keys(@stored_sunset)) == @stored_sunset
    end

    test "re-enabling override reveals the stored local values", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      set_override(view, false, true)

      assert_editable(view, @sunset_fields)
      assert has_element?(view, "#{input("sunset_time")}[value='17:30:00']")
      assert has_element?(view, "#{input("min_sunset_time")}[value='17:00:00']")
      assert has_element?(view, "#{input("sunset_offset")}[value='300']")
    end

    test "values submitted for locked controls cannot replace stored values", %{conn: conn} do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      # Valid on their own, so only the lock can keep them out of the stored config.
      html =
        render_submit(view, "save", %{
          "min_sunset_time" => "17:10:00",
          "sunset_time" => "",
          "sunset_offset" => "0",
          "brightness_mode_time_dark" => "900",
          "save_action" => "save"
        })

      assert html =~ "Light state saved."
      assert Map.take(persisted(state.id), Map.keys(@stored_sunset)) == @stored_sunset
    end

    test "toggle, save, reload, and duplicate keep the stored values", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      set_override(view, false, true)
      render_submit(view, "save", %{"sunset_time" => "17:35:00", "save_action" => "save"})

      assert persisted(state.id)["override_sunset_timing"] == true
      assert persisted(state.id)["sunset_time"] == "17:35:00"

      set_override(view, false, false)
      render_submit(view, "save", %{"save_action" => "save"})

      assert persisted(state.id)["override_sunset_timing"] == false
      assert persisted(state.id)["sunset_time"] == "17:35:00"

      {:ok, reloaded, _html} = live(conn, "/config/light-states/#{state.id}/edit")
      refute has_element?(reloaded, "#light-state-override_sunset_timing[checked]")
      assert_locked(reloaded, @sunset_fields)

      {:ok, copy} = Scenes.duplicate_light_state(state.id)
      assert persisted(copy.id) == persisted(state.id)

      {:ok, copied, _html} = live(conn, "/config/light-states/#{copy.id}/edit")
      set_override(copied, false, true)
      assert has_element?(copied, "#{input("sunset_time")}[value='17:35:00']")
    end
  end

  describe "shared ramp durations" do
    test "are locked at their defaults when both events inherit", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      assert_locked(view, @ramp_fields)
      assert has_element?(view, "#{input("brightness_mode_time_dark")}[value='900']")
      assert has_element?(view, "#{input("brightness_mode_time_light")}[value='3600']")
      assert has_element?(view, "#light-state-ramp-note", "Both events inherit")
      assert persisted(state.id)["brightness_mode_time_dark"] == 1800
    end

    test "stay editable with a scoped note when one event overrides", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      set_override(view, true, false)

      assert_editable(view, @ramp_fields)
      assert has_element?(view, "#{input("brightness_mode_time_dark")}[value='1800']")
      assert has_element?(view, "#light-state-ramp-note", "apply only around sunrise")
      assert has_element?(view, "#light-state-ramp-note", "900 s dark and 3600 s light")
      assert_editable(view, @sunrise_fields)
      assert_locked(view, @sunset_fields)

      set_override(view, false, true)

      assert has_element?(view, "#light-state-ramp-note", "apply only around sunset")
      assert_locked(view, @sunrise_fields)
      assert_editable(view, @sunset_fields)
    end

    test "need no note when both events override", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      set_override(view, true, true)

      assert_editable(view, @ramp_fields)
      refute has_element?(view, "#light-state-ramp-note")
    end

    test "explain themselves in a full-width note outside the field group", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      assert has_element?(view, ".hw-field-flow > .hw-field-flow-note > #light-state-ramp-note")
      refute has_element?(view, ".hw-field-group #light-state-ramp-note")

      set_override(view, true, false)

      assert has_element?(view, ".hw-field-flow > .hw-field-flow-note > #light-state-ramp-note")
    end
  end

  describe "override toggles" do
    test "keep their note on a full-width row above the fields", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      for event <- ~w(sunrise sunset) do
        note = ".hw-field-flow > .hw-field-flow-note"

        assert has_element?(view, "#{note} > #light-state-#{event}-timing-note")
        assert has_element?(view, "#{note} > .hw-toggle > #light-state-override_#{event}_timing")
      end
    end
  end

  describe "a dormant inverted local window" do
    setup do
      state =
        stored_profile(%{
          "override_sunset_timing" => false,
          "min_sunset_time" => "20:00:00",
          "max_sunset_time" => "18:00:00"
        })

      %{state: state}
    end

    test "does not disturb the preview while inheriting", %{conn: conn, state: state} do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:30"})
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      render_change(view, "update_form", %{"preview_date" => "2026-12-21"})
      assigns = assigns_of(view)

      assert assigns.circadian_preview_error == nil

      assert Enum.find(assigns.circadian_preview.markers, &(&1.key == :sunset)).time_label ==
               "18:30"

      assert has_element?(view, "#{input("max_sunset_time")}[disabled][value='']")
    end

    test "survives saving while inheriting", %{conn: conn, state: state} do
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      html = render_submit(view, "save", %{"min_brightness" => "20", "save_action" => "save"})

      assert html =~ "Light state saved."
      assert persisted(state.id)["min_sunset_time"] == "20:00:00"
      assert persisted(state.id)["max_sunset_time"] == "18:00:00"
    end

    test "is rejected when the override is re-enabled", %{conn: conn, state: state} do
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      set_override(view, false, true)

      assert assigns_of(view).circadian_preview_error =~ "min_sunset_time"

      html = render_submit(view, "save", %{"save_action" => "save"})

      assert html =~ "min_sunset_time"
      assert persisted(state.id)["override_sunset_timing"] == false

      set_override(view, false, false)

      assert assigns_of(view).circadian_preview_error == nil
    end
  end

  describe "a legacy profile" do
    test "opens with both overrides on and keeps local timing when saved", %{conn: conn} do
      state =
        Repo.insert!(%LightState{
          name: "Legacy",
          type: :circadian,
          config: %{sunset_time: "18:30:00", min_sunset_time: "18:00:00"}
        })

      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      assert has_element?(view, "#light-state-override_sunrise_timing[checked]")
      assert has_element?(view, "#light-state-override_sunset_timing[checked]")
      assert has_element?(view, "#{input("sunset_time")}:not([disabled])[value='18:30:00']")

      render_submit(view, "save", %{"save_action" => "save"})

      config = persisted(state.id)

      assert config["override_sunset_timing"] == true
      assert config["sunset_time"] == "18:30:00"
      assert config["min_sunset_time"] == "18:00:00"
    end
  end

  describe "preview" do
    test "matches runtime for unsaved edits and global bounds", %{conn: conn} do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      render_change(view, "update_form", %{
        "preview_date" => "2026-12-21",
        "override_sunset_timing" => "false",
        "override_sunrise_timing" => "true"
      })

      render_change(view, "update_form", %{"sunrise_time" => "07:45:00"})

      assigns = assigns_of(view)
      preview = assigns.circadian_preview
      unsaved = assigns.light_state_config

      assert Enum.find(preview.markers, &(&1.key == :sunrise)).time_label == "07:45"
      assert Enum.find(preview.markers, &(&1.key == :sunset)).time_label == "18:00"
      assert Enum.find(preview.brightness_markers, &(&1.key == :sunset)).time_label == "18:00"
      assert Enum.find(preview.temperature_markers, &(&1.key == :sunset)).time_label == "18:00"

      solar_config = AppSettings.solar_config()

      for point <- preview.points do
        time = Time.new!(div(point.minute, 60), rem(point.minute, 60), 0)
        now = DateTime.new!(~D[2026-12-21], time, "America/Los_Angeles")
        {:ok, direct} = Circadian.calculate(unsaved, solar_config, now)

        assert {point.brightness, point.kelvin} == {direct.brightness, direct.kelvin}
      end

      # Nothing was saved along the way.
      assert persisted(state.id)["override_sunrise_timing"] == false
      assert persisted(state.id)["sunrise_time"] == nil
    end

    test "explains astronomical unavailability", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/config/light-states/new/circadian")

      html =
        render_change(view, "update_form", %{
          "preview_date" => "2026-06-21",
          "preview_timezone" => "Europe/Oslo",
          "preview_latitude" => "69.6492",
          "preview_longitude" => "18.9553"
        })

      assert html =~ "no astronomical sunrise at this latitude on 2026-06-21"
    end
  end

  describe "live global updates" do
    test "refresh locked values and the preview without losing unsaved edits", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      render_change(view, "update_form", %{
        "name" => "Unsaved Name",
        "min_brightness" => "25",
        "preview_date" => "2026-12-21"
      })

      assert %{dirty: true} = assigns_of(view)

      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      html = render(view)

      assert has_element?(view, "#{input("min_sunset_time")}[disabled][value='18:00:00']")
      assert html =~ "a global minimum of 18:00:00"

      assigns = assigns_of(view)

      assert Enum.find(assigns.circadian_preview.markers, &(&1.key == :sunset)).time_label ==
               "18:00"

      assert assigns.dirty == true
      assert assigns.light_state_name == "Unsaved Name"
      assert assigns.light_state_config["min_brightness"] == "25"
    end

    test "an unrelated settings change leaves the preview alone", %{conn: conn} do
      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      before_assigns = assigns_of(view)

      {:ok, _settings} = AppSettings.upsert_global(%{default_transition_ms: 900})
      _html = render(view)

      assert assigns_of(view).circadian_preview == before_assigns.circadian_preview
    end

    test "credentials stay out of the LiveView assigns", %{conn: conn} do
      {:ok, _settings} =
        AppSettings.upsert_global(%{
          ha_export_scenes_enabled: true,
          ha_export_mqtt_host: "mqtt.local",
          ha_export_mqtt_password: "broker-secret"
        })

      state = stored_profile()
      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      _html = render(view)

      refute inspect(assigns_of(view), limit: :infinity, printable_limit: :infinity) =~
               "broker-secret"
    end
  end

  describe "saving" do
    test "reports an event order conflict and leaves the profile alone", %{conn: conn} do
      state =
        stored_profile(%{"override_sunrise_timing" => true, "override_sunset_timing" => true})

      {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

      html =
        render_submit(view, "save", %{
          "sunset_time" => "18:00:00",
          "min_sunset_time" => "",
          "max_sunset_time" => "",
          "sunset_offset" => "0",
          "sunrise_time" => "06:00:00",
          "brightness_sunrise_offset" => "36000",
          "brightness_sunset_offset" => "-36000",
          "save_action" => "save"
        })

      assert html =~ "would put sunrise and sunset out of order for: Default Circadian"
      assert persisted(state.id)["brightness_sunrise_offset"] == nil
    end
  end
end
