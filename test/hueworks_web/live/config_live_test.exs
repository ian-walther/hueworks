defmodule HueworksWeb.ConfigLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.AppSettings
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, Bridge, LightState, Room, SceneComponent}

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    :ok
  end

  test "shows global solar settings form and saves values", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config")

    assert html =~ "Global Solar Settings"
    assert html =~ "Light State Configs"
    assert html =~ "Save Global Settings"
    assert html =~ "Default Transition (ms)"

    view
    |> form("form[phx-submit='save_global_solar']", %{
      "timezone" => "America/Chicago",
      "latitude" => "41.8781",
      "longitude" => "-87.6298",
      "default_transition_ms" => "900"
    })
    |> render_submit()

    assert render(view) =~ "Global solar settings saved."

    settings = AppSettings.get_global()
    assert settings.latitude == 41.8781
    assert settings.longitude == -87.6298
    assert settings.timezone == "America/Chicago"
    assert settings.default_transition_ms == 900
  end

  test "shows light state actions and list entries", %{conn: conn} do
    {:ok, _manual} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})
    {:ok, _circadian} = Scenes.create_light_state("Circadian A", :circadian, %{})

    {:ok, _view, html} = live(conn, "/config")

    assert html =~ "New Manual"
    assert html =~ "New Circadian"
    assert html =~ "Soft (manual temp)"
    assert html =~ "Circadian A (circadian)"
  end

  test "duplicate light state action navigates to the copied editor", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})

    {:ok, view, _html} = live(conn, "/config")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("button[phx-click='duplicate_light_state'][phx-value-id='#{state.id}']")
             |> render_click()

    copy = Repo.get_by!(LightState, name: "Soft Copy")
    assert to == "/config/light-states/#{copy.id}/edit"
  end

  test "delete light state removes unused state from the list", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})

    {:ok, view, _html} = live(conn, "/config")

    view
    |> element("button[phx-click='delete_light_state'][phx-value-id='#{state.id}']")
    |> render_click()

    refute Repo.get(LightState, state.id)
    refute render(view) =~ "Soft (manual temp)"
  end

  test "delete light state is disabled and shows usage info when in use", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Studio", metadata: %{}})
    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    Repo.insert!(%SceneComponent{
      name: "Component 1",
      scene_id: scene.id,
      light_state_id: state.id
    })

    {:ok, view, html} = live(conn, "/config")

    assert html =~ "Studio / Chill"

    assert has_element?(
             view,
             "button[phx-click='delete_light_state'][phx-value-id='#{state.id}'][disabled]"
           )
  end

  test "handles geolocation event by prefilling lat/lon and timezone", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config")

    render_hook(view, "geolocation_success", %{
      "latitude" => 40.7128,
      "longitude" => -74.0060,
      "timezone" => "America/New_York"
    })

    html = render(view)
    assert html =~ "Location and timezone received from browser."
    assert html =~ "40.712800"
    assert html =~ "-74.006000"
    assert html =~ ~s(value="America/New_York" selected)
  end

  test "shows persisted timezone even when it is outside the curated timezone shortlist", %{
    conn: conn
  } do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/Indiana/Indianapolis",
      default_transition_ms: 750
    })

    {:ok, _view, html} = live(conn, "/config")

    assert html =~ ~s(value="America/Indiana/Indianapolis")
    assert html =~ ~s(value="750")

    assert html =~
             ~r/<option[^>]*value="America\/Indiana\/Indianapolis"[^>]*selected/
  end

  test "shows Scene Import button for Home Assistant bridges", %{conn: conn} do
    Repo.insert!(%Bridge{
      type: :ha,
      name: "Home Assistant",
      host: "10.0.0.90",
      credentials: %{"token" => "token"},
      enabled: true,
      import_complete: true
    })

    {:ok, _view, html} = live(conn, "/config")

    assert html =~ "Scene Import"
    assert html =~ "/config/bridge/"
    assert html =~ "/external-scenes"
  end
end
