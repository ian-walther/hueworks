defmodule HueworksWeb.LightStateEditorLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, LightState, Room, SceneComponent}

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)

    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      default_transition_ms: 0
    })

    :ok
  end

  defp insert_room do
    Repo.insert!(%Room{name: "Studio", metadata: %{}})
  end

  test "new manual editor renders manual controls and creates a temperature state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config/light-states/new/manual")

    assert html =~ "New Manual Light State"
    assert html =~ "Temperature"
    assert html =~ "Brightness"
    assert html =~ "Revert"
    assert html =~ "Save and Return"
    refute html =~ "Circadian Preview"

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             render_submit(view, "save", %{
               "name" => "Warm",
               "mode" => "temperature",
               "brightness" => "55",
               "temperature" => "3000",
               "save_action" => "save_and_return"
             })

    state = Repo.get_by!(LightState, name: "Warm")
    assert state.type == :manual
    assert LightState.persisted_config(state)["brightness"] == 55
    assert LightState.persisted_config(state)["temperature"] == 3000
  end

  test "new manual editor creates a color state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/light-states/new/manual")

    view
    |> form("form[phx-change='update_form']", %{
      "mode" => "color"
    })
    |> render_change()

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             render_submit(view, "save", %{
               "name" => "Blue",
               "mode" => "color",
               "brightness" => "75",
               "hue" => "210",
               "saturation" => "60",
               "save_action" => "save_and_return"
             })

    state = Repo.get_by!(LightState, name: "Blue")
    assert state.type == :manual
    assert LightState.persisted_config(state)["mode"] == "color"
    assert LightState.persisted_config(state)["brightness"] == 75
    assert LightState.persisted_config(state)["hue"] == 210
    assert LightState.persisted_config(state)["saturation"] == 60
  end

  test "edit editor updates an existing manual state", %{conn: conn} do
    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "2700"})

    {:ok, view, html} = live(conn, "/config/light-states/#{state.id}/edit")

    assert html =~ "Edit Light State"
    assert html =~ ~s(value="Soft")

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             render_submit(view, "save", %{
               "name" => "Soft Updated",
               "mode" => "temperature",
               "brightness" => "65",
               "temperature" => "3200",
               "save_action" => "save_and_return"
             })

    updated = Repo.get!(LightState, state.id)
    assert updated.name == "Soft Updated"
    assert LightState.persisted_config(updated)["brightness"] == 65
    assert LightState.persisted_config(updated)["temperature"] == 3200
  end

  test "edit editor renders atom-keyed manual color config values", %{conn: conn} do
    state =
      Repo.insert!(%LightState{
        name: "Blue",
        type: :manual,
        config: %{mode: :color, brightness: 75, hue: 210, saturation: 60}
      })

    {:ok, _view, html} = live(conn, "/config/light-states/#{state.id}/edit")

    assert html =~ ~s(value="75")
    assert html =~ ~s(value="210")
    assert html =~ ~s(value="60")
    assert html =~ ~s(<option value="color" selected="selected">Color</option>)
  end

  test "new circadian editor renders and saves all circadian inputs", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config/light-states/new/circadian")

    assert html =~ "New Circadian Light State"
    assert html =~ "Brightness Mode"
    assert html =~ "Brightness Range"
    assert html =~ "Temperature Range"
    assert html =~ "Ceiling"
    assert html =~ "Sunrise Window"
    assert html =~ "Sunset Window"
    assert html =~ "Circadian Preview"
    assert html =~ "Solar Timing"
    assert html =~ "Brightness Curve"
    assert html =~ "Temperature Curve"
    assert html =~ "Curve Offsets (s)"
    assert html =~ "Preview Date"
    assert html =~ "Preview Latitude"
    assert html =~ "Revert"
    assert html =~ "Save and Return"
    assert html =~ ~s(phx-hook="CircadianChart")
    assert html =~ ~s(id="circadian-brightness-card")
    assert html =~ ~s(id="circadian-kelvin-card")
    assert html =~ ~s(data-role="tooltip")
    assert html =~ ~s(aria-label="Explain Brightness Mode")
    assert html =~ ~s(<option value="tanh" selected="selected">tanh</option>)
    assert html =~ "Quadratic uses the original parabolic overnight ramp"
    assert html =~ "After sunrise is chosen and the sunrise offset is applied"
    assert html =~ "Used only for linear and tanh"

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             render_submit(view, "save", %{
               "name" => "Circadian A",
               "brightness_mode" => "linear",
               "min_brightness" => "5",
               "max_brightness" => "95",
               "min_color_temp" => "2100",
               "max_color_temp" => "5000",
               "temperature_ceiling_kelvin" => "4200",
               "sunrise_time" => "06:30:00",
               "min_sunrise_time" => "05:45:00",
               "max_sunrise_time" => "07:00:00",
               "sunrise_offset" => "-900",
               "sunset_time" => "19:30:00",
               "min_sunset_time" => "18:45:00",
               "max_sunset_time" => "20:15:00",
               "sunset_offset" => "1200",
               "brightness_sunrise_offset" => "-300",
               "brightness_sunset_offset" => "600",
               "temperature_sunrise_offset" => "-600",
               "temperature_sunset_offset" => "900",
               "brightness_mode_time_dark" => "1200",
               "brightness_mode_time_light" => "5400",
               "save_action" => "save_and_return"
             })

    state = Repo.get_by!(LightState, name: "Circadian A")
    assert state.type == :circadian
    assert LightState.persisted_config(state)["brightness_mode"] == "linear"
    assert LightState.persisted_config(state)["min_brightness"] == 5
    assert LightState.persisted_config(state)["max_brightness"] == 95
    assert LightState.persisted_config(state)["min_color_temp"] == 2100
    assert LightState.persisted_config(state)["max_color_temp"] == 5000
    assert LightState.persisted_config(state)["temperature_ceiling_kelvin"] == 4200
    assert LightState.persisted_config(state)["sunrise_time"] == "06:30:00"
    assert LightState.persisted_config(state)["min_sunrise_time"] == "05:45:00"
    assert LightState.persisted_config(state)["max_sunrise_time"] == "07:00:00"
    assert LightState.persisted_config(state)["sunrise_offset"] == -900
    assert LightState.persisted_config(state)["sunset_time"] == "19:30:00"
    assert LightState.persisted_config(state)["min_sunset_time"] == "18:45:00"
    assert LightState.persisted_config(state)["max_sunset_time"] == "20:15:00"
    assert LightState.persisted_config(state)["sunset_offset"] == 1200
    assert LightState.persisted_config(state)["brightness_sunrise_offset"] == -300
    assert LightState.persisted_config(state)["brightness_sunset_offset"] == 600
    assert LightState.persisted_config(state)["temperature_sunrise_offset"] == -600
    assert LightState.persisted_config(state)["temperature_sunset_offset"] == 900
    assert LightState.persisted_config(state)["brightness_mode_time_dark"] == 1200
    assert LightState.persisted_config(state)["brightness_mode_time_light"] == 5400
  end

  test "circadian preview responds to preview input changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/light-states/new/circadian")

    html =
      view
      |> form("form[phx-change='update_form']", %{
        "preview_date" => "2026-03-08",
        "preview_timezone" => "America/New_York",
        "preview_latitude" => "40.712800",
        "preview_longitude" => "-74.006000",
        "sunrise_time" => "06:30:00",
        "sunset_time" => "19:15:00"
      })
      |> render_change()

    assert html =~ ~s(value="2026-03-08")
    assert html =~ ~s(value="America/New_York" selected)
    assert html =~ "Brightness Curve"
    assert html =~ "Temperature Curve"
    assert html =~ ~s(data-points=)
  end

  test "circadian preview errors keep inputs visible and replace charts with placeholders", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/config/light-states/new/circadian")

    _html =
      view
      |> form("form[phx-change='update_form']", %{
        "min_sunrise_time" => "08:00:00",
        "max_sunrise_time" => "06:00:00"
      })
      |> render_change()

    html = render(view)

    assert html =~ "Preview unavailable:"
    assert html =~ "Solar Timing"
    assert html =~ "Brightness Curve"
    assert html =~ "Temperature Curve"
    assert html =~ ~s(id="light-state-min_sunrise_time")
    assert html =~ ~s(id="light-state-brightness-mode")
    assert html =~ ~s(id="light-state-min_color_temp")
    assert html =~ ">...<"

    assert String.split(html, "hw-chart-placeholder") |> length() == 3
    refute html =~ ~s(<svg class="hw-chart")
  end

  test "circadian editor rejects a temperature ceiling below the minimum color temperature", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/config/light-states/new/circadian")

    html =
      render_submit(view, "save", %{
        "name" => "Invalid Ceiling",
        "min_color_temp" => "2200",
        "max_color_temp" => "5000",
        "temperature_ceiling_kelvin" => "2000",
        "save_action" => "save_and_return"
      })

    assert html =~ "temperature_ceiling_kelvin"
    assert html =~ "must be greater than or equal to min_color_temp"
  end

  test "edit editor renders an existing circadian state", %{conn: conn} do
    {:ok, state} =
      Scenes.create_light_state("Circadian Existing", :circadian, %{
        "min_brightness" => "30",
        "max_brightness" => "100",
        "min_color_temp" => "2000",
        "max_color_temp" => "5500",
        "brightness_mode" => "tanh",
        "brightness_mode_time_dark" => "5400",
        "brightness_mode_time_light" => "900"
      })

    {:ok, _view, html} = live(conn, "/config/light-states/#{state.id}/edit")

    assert html =~ "Edit Light State"
    assert html =~ ~s(value="Circadian Existing")
    assert html =~ ~s(id="light-state-min_brightness")
    assert html =~ ~s(value="30")
    assert html =~ ~s(id="light-state-brightness-mode")
    assert html =~ ~s(value="tanh" selected)
  end

  test "edit editor updates an existing circadian state", %{conn: conn} do
    {:ok, state} =
      Scenes.create_light_state("Circadian Existing", :circadian, %{
        "min_brightness" => "30",
        "max_brightness" => "100",
        "min_color_temp" => "2000",
        "max_color_temp" => "5500",
        "brightness_mode" => "tanh"
      })

    {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             render_submit(view, "save", %{
               "name" => "Circadian Updated",
                "brightness_mode" => "linear",
                "min_brightness" => "20",
                "max_brightness" => "90",
                "min_color_temp" => "2200",
                "max_color_temp" => "5000",
                "sunrise_offset" => "0",
                "sunset_offset" => "0",
                "brightness_mode_time_dark" => "5400",
                "brightness_mode_time_light" => "900",
                "save_action" => "save_and_return"
              })

    updated = Repo.get!(LightState, state.id)
    assert updated.name == "Circadian Updated"
    assert LightState.persisted_config(updated)["brightness_mode"] == "linear"
    assert LightState.persisted_config(updated)["min_brightness"] == 20
    assert LightState.persisted_config(updated)["max_brightness"] == 90
    assert LightState.persisted_config(updated)["min_color_temp"] == 2200
    assert LightState.persisted_config(updated)["max_color_temp"] == 5000
  end

  test "save keeps a new light state in the editor on its edit route", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/light-states/new/manual")

    render_submit(view, "save", %{
      "name" => "Stay Here",
      "mode" => "temperature",
      "brightness" => "42",
      "temperature" => "2800",
      "save_action" => "save"
    })

    state = Repo.get_by!(LightState, name: "Stay Here")
    assert_patch(view, "/config/light-states/#{state.id}/edit")

    html = render(view)
    assert html =~ "Edit Light State"
    assert html =~ ~s(value="Stay Here")
  end

  test "revert restores the last loaded values", %{conn: conn} do
    {:ok, state} =
      Scenes.create_manual_light_state("Revert Me", %{
        "brightness" => "40",
        "temperature" => "2700"
      })

    {:ok, view, _html} = live(conn, "/config/light-states/#{state.id}/edit")

    view
    |> form("form[phx-change='update_form']", %{
      "name" => "Changed",
      "mode" => "temperature",
      "brightness" => "65",
      "temperature" => "3200"
    })
    |> render_change()

    html =
      view
      |> element("button[phx-click='revert']")
      |> render_click()

    assert html =~ ~s(value="Revert Me")
    assert html =~ ~s(name="brightness")
    assert html =~ ~s(value="40")
    assert html =~ ~s(name="temperature")
    assert html =~ ~s(value="2700")
  end

  test "edit editor shows where a light state is used", %{conn: conn} do
    room = insert_room()

    insert_bridge!(%{
      type: :hue,
      name: "Hue Bridge",
      host: "10.0.0.230",
      credentials: %{"api_key" => "key"},
      import_complete: false,
      enabled: true
    })

    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    Repo.insert!(%SceneComponent{
      name: "Component 1",
      scene_id: scene.id,
      light_state_id: state.id
    })

    {:ok, _view, html} = live(conn, "/config/light-states/#{state.id}/edit")

    assert html =~ "Used by 1 scene"
    assert html =~ "Studio / Chill"
  end
end
