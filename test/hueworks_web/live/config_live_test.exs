defmodule HueworksWeb.ConfigLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.AppSettings
  alias Hueworks.Repo
  alias Hueworks.Schemas.AppSetting

  setup do
    Repo.delete_all(AppSetting)
    :ok
  end

  test "shows global solar settings form and saves values", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config")

    assert html =~ "Global Solar Settings"
    assert html =~ "Save Global Settings"

    view
    |> form("form[phx-submit='save_global_solar']", %{
      "timezone" => "America/Chicago",
      "latitude" => "41.8781",
      "longitude" => "-87.6298"
    })
    |> render_submit()

    assert render(view) =~ "Global solar settings saved."

    settings = AppSettings.get_global()
    assert settings.latitude == 41.8781
    assert settings.longitude == -87.6298
    assert settings.timezone == "America/Chicago"
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
      timezone: "America/Indiana/Indianapolis"
    })

    {:ok, _view, html} = live(conn, "/config")

    assert html =~ ~s(value="America/Indiana/Indianapolis")

    assert html =~
             ~r/<option[^>]*value="America\/Indiana\/Indianapolis"[^>]*selected/
  end
end
