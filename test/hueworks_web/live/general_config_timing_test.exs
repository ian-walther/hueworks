defmodule HueworksWeb.GeneralConfigTimingTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.AppSettings
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.AppSetting

  @form "form[phx-submit='save_global_solar']"

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

  defp persisted, do: Repo.get_by!(AppSetting, scope: "global")

  test "shows all four bounds blank by default", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config/general")

    assert html =~ "Sunrise and sunset bounds"

    for field <- ~w(min_sunrise_time max_sunrise_time min_sunset_time max_sunset_time) do
      assert has_element?(view, "#global_#{field}[type='time'][value='']")
    end
  end

  test "saves a bound and returns to config", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    assert {:error, {:live_redirect, %{to: "/config"}}} =
             view
             |> form(@form, %{"min_sunset_time" => "18:00"})
             |> render_submit()

    assert persisted().min_sunset_time == "18:00:00"
    assert persisted().max_sunset_time == nil
  end

  test "an empty input clears a bound while midnight stays real", %{conn: conn} do
    {:ok, _settings} =
      AppSettings.upsert_global(%{min_sunset_time: "18:00", min_sunrise_time: "06:00"})

    {:ok, view, _html} = live(conn, "/config/general")

    assert has_element?(view, "#global_min_sunset_time[value='18:00:00']")

    view
    |> form(@form, %{"min_sunset_time" => "", "min_sunrise_time" => "00:00"})
    |> render_submit()

    assert persisted().min_sunset_time == nil
    assert persisted().min_sunrise_time == "00:00:00"
  end

  test "an inverted pair shows a labeled error and saves nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    view
    |> form(@form, %{"min_sunset_time" => "20:00", "max_sunset_time" => "18:00"})
    |> render_submit()

    html = render(view)

    assert html =~ "Sunset minimum must be less than or equal to sunset maximum"
    assert persisted().min_sunset_time == nil
    assert persisted().max_sunset_time == nil
  end

  test "a malformed time shows a labeled error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    render_submit(view, "save_global_solar", %{"min_sunset_time" => "evening"})

    assert render(view) =~ "Sunset minimum must be HH:MM[:SS]"
    assert persisted().min_sunset_time == nil
  end

  test "an event order conflict names the affected profile", %{conn: conn} do
    {:ok, _state} =
      Scenes.create_light_state("Warm Circadian", :circadian, %{
        "override_sunset_timing" => true,
        "sunset_time" => "18:00:00",
        "brightness_sunset_offset" => -18_000
      })

    {:ok, view, _html} = live(conn, "/config/general")

    view
    |> form(@form, %{"min_sunrise_time" => "10:00"})
    |> render_submit()

    assert render(view) =~ "would put sunrise and sunset out of order for: Warm Circadian"
    assert persisted().min_sunrise_time == nil
  end

  test "a save patches only edited fields over the latest persisted row", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    # Committed by another writer before this form hears about it.
    Repo.update_all(AppSetting,
      set: [min_sunset_time: "19:00:00", default_transition_ms: 1234]
    )

    view
    |> form(@form, %{"max_sunset_time" => "21:00"})
    |> render_submit()

    assert persisted().min_sunset_time == "19:00:00"
    assert persisted().max_sunset_time == "21:00:00"
    assert persisted().default_transition_ms == 1234
  end

  test "an equivalent time submitted without seconds is not an edit", %{conn: conn} do
    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
    {:ok, view, _html} = live(conn, "/config/general")

    Repo.update_all(AppSetting, set: [min_sunset_time: "19:00:00"])

    render_submit(view, "save_global_solar", %{"min_sunset_time" => "18:00"})

    assert persisted().min_sunset_time == "19:00:00"
  end

  for value <- ["18:00:00Z", "18:00:00+05:00", "18:00:00.5"] do
    test "#{value} is rejected rather than read as the persisted time", %{conn: conn} do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      {:ok, view, _html} = live(conn, "/config/general")

      render_submit(view, "save_global_solar", %{"min_sunset_time" => unquote(value)})

      assert render(view) =~ "Sunset minimum must be HH:MM[:SS]"
      assert persisted().min_sunset_time == "18:00:00"
    end
  end

  test "shows another writer's commit live", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
    _html = render(view)

    assert has_element?(view, "#global_min_sunset_time[value='18:00:00']")

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: ""})
    _html = render(view)

    assert has_element?(view, "#global_min_sunset_time[value='']")
  end

  test "a live update does not overwrite this form's unsaved edits", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    view
    |> form(@form, %{"latitude" => "40.0", "max_sunset_time" => "20:00"})
    |> render_change()

    {:ok, _settings} =
      AppSettings.upsert_global(%{min_sunset_time: "18:00", max_sunset_time: "22:00"})

    _html = render(view)

    assert has_element?(view, "#global_min_sunset_time[value='18:00:00']")
    assert has_element?(view, "#global_max_sunset_time[value='20:00']")
    assert has_element?(view, "#global_latitude[value='40.0']")

    view |> form(@form) |> render_submit()

    assert persisted().min_sunset_time == "18:00:00"
    assert persisted().max_sunset_time == "20:00:00"
    assert persisted().latitude == 40.0
  end

  test "credentials stay out of the LiveView assigns", %{conn: conn} do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        ha_export_scenes_enabled: true,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_mqtt_password: "broker-secret"
      })

    {:ok, view, _html} = live(conn, "/config/general")

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
    _html = render(view)

    assigns = :sys.get_state(view.pid).socket.assigns

    refute inspect(assigns, limit: :infinity, printable_limit: :infinity) =~ "broker-secret"
  end
end
