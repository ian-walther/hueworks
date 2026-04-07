defmodule HueworksWeb.LightStateEditorLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, Bridge, LightState, Room, SceneComponent}

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
    refute html =~ "Circadian Preview"

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             view
             |> form("form[phx-submit='save']", %{
               "name" => "Warm",
               "mode" => "temperature",
               "brightness" => "55",
               "temperature" => "3000"
             })
             |> render_submit()

    state = Repo.get_by!(LightState, name: "Warm")
    assert state.type == :manual
    assert state.config["brightness"] == 55
    assert state.config["temperature"] == 3000
  end

  test "new manual editor creates a color state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/light-states/new/manual")

    view
    |> form("form[phx-change='update_form']", %{
      "mode" => "color"
    })
    |> render_change()

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             view
             |> form("form[phx-submit='save']", %{
               "name" => "Blue",
               "mode" => "color",
               "brightness" => "75",
               "hue" => "210",
               "saturation" => "60"
             })
             |> render_submit()

    state = Repo.get_by!(LightState, name: "Blue")
    assert state.type == :manual
    assert state.config["mode"] == "color"
    assert state.config["brightness"] == 75
    assert state.config["hue"] == 210
    assert state.config["saturation"] == 60
  end

  test "edit editor updates an existing manual state", %{conn: conn} do
    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "2700"})

    {:ok, view, html} = live(conn, "/config/light-states/#{state.id}/edit")

    assert html =~ "Edit Light State"
    assert html =~ ~s(value="Soft")

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             view
             |> form("form[phx-submit='save']", %{
               "name" => "Soft Updated",
               "mode" => "temperature",
               "brightness" => "65",
               "temperature" => "3200"
             })
             |> render_submit()

    updated = Repo.get!(LightState, state.id)
    assert updated.name == "Soft Updated"
    assert updated.config["brightness"] == 65
    assert updated.config["temperature"] == 3200
  end

  test "new circadian editor renders and saves all circadian inputs", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config/light-states/new/circadian")

    assert html =~ "New Circadian Light State"
    assert html =~ "Brightness Mode"
    assert html =~ "Min Brightness (%)"
    assert html =~ "Sunrise Time"
    assert html =~ "Circadian Preview"
    assert html =~ "Brightness Curve"
    assert html =~ "Temperature Curve"
    assert html =~ "Preview Date"
    assert html =~ "Preview Latitude"
    assert html =~ ~s(phx-hook="CircadianChart")
    assert html =~ ~s(data-role="tooltip")

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             view
             |> form("form[phx-submit='save']", %{
               "name" => "Circadian A",
               "brightness_mode" => "linear",
               "min_brightness" => "5",
               "max_brightness" => "95",
               "min_color_temp" => "2100",
               "max_color_temp" => "5000",
               "sunrise_time" => "06:30:00",
               "min_sunrise_time" => "05:45:00",
               "max_sunrise_time" => "07:00:00",
               "sunrise_offset" => "-900",
               "sunset_time" => "19:30:00",
               "min_sunset_time" => "18:45:00",
               "max_sunset_time" => "20:15:00",
               "sunset_offset" => "1200",
               "brightness_mode_time_dark" => "1200",
               "brightness_mode_time_light" => "5400"
             })
             |> render_submit()

    state = Repo.get_by!(LightState, name: "Circadian A")
    assert state.type == :circadian
    assert state.config["brightness_mode"] == "linear"
    assert state.config["min_brightness"] == 5
    assert state.config["max_brightness"] == 95
    assert state.config["min_color_temp"] == 2100
    assert state.config["max_color_temp"] == 5000
    assert state.config["sunrise_time"] == "06:30:00"
    assert state.config["min_sunrise_time"] == "05:45:00"
    assert state.config["max_sunrise_time"] == "07:00:00"
    assert state.config["sunrise_offset"] == -900
    assert state.config["sunset_time"] == "19:30:00"
    assert state.config["min_sunset_time"] == "18:45:00"
    assert state.config["max_sunset_time"] == "20:15:00"
    assert state.config["sunset_offset"] == 1200
    assert state.config["brightness_mode_time_dark"] == 1200
    assert state.config["brightness_mode_time_light"] == 5400
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

  test "edit editor shows where a light state is used", %{conn: conn} do
    room = insert_room()

    Repo.insert!(%Bridge{
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
