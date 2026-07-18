defmodule HueworksWeb.AreasLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Schemas.Area
  alias Hueworks.Scenes

  test "areas page renders existing areas", %{conn: conn} do
    area = Repo.insert!(%Area{name: "Studio", metadata: %{}})

    {:ok, view, html} = live(conn, "/areas")

    assert html =~ "Areas"
    assert html =~ "Studio"
    assert html =~ "area-#{area.id}"
    assert has_element?(view, "main.hw-content-frame .hw-page-header", "House structure")
    assert has_element?(view, "#area-#{area.id}.hw-area-ledger-card")
    assert has_element?(view, "#area-#{area.id} .hw-area-ledger-body")
    assert has_element?(view, "#area-#{area.id} .hw-area-details", "Area details")
  end

  test "areas page creates a area through the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/areas")

    render_click(element(view, "button[phx-click='open_new']"))

    html =
      view
      |> form("form[phx-submit='save_area']", %{"name" => "Guest Area"})
      |> render_submit()

    assert html =~ "Guest Area"

    area = Repo.get_by!(Area, name: "Guest Area")
    assert area.display_name == nil
  end

  test "areas page updates a area display name through the modal", %{conn: conn} do
    area = Repo.insert!(%Area{name: "Studio", metadata: %{}})

    {:ok, view, _html} = live(conn, "/areas")

    render_click(element(view, "#area-#{area.id} button[phx-click='open_edit']"))

    html =
      view
      |> form("form[phx-submit='save_area']", %{"name" => "Creative Studio"})
      |> render_submit()

    assert html =~ "Creative Studio"

    updated = Repo.get!(Area, area.id)
    assert updated.display_name == "Creative Studio"
  end

  test "areas page deletes a area", %{conn: conn} do
    area = Repo.insert!(%Area{name: "Guest Area", metadata: %{}})

    {:ok, view, _html} = live(conn, "/areas")

    assert has_element?(
             view,
             "#area-#{area.id} button[phx-click='delete_area'][data-confirm]"
           )

    view
    |> element("#area-#{area.id} button[phx-click='delete_area']")
    |> render_click()

    refute Repo.get(Area, area.id)
    refute render(view) =~ "Guest Area"
  end

  test "areas page deletes a scene from the area card", %{conn: conn} do
    area = Repo.insert!(%Area{name: "Studio", metadata: %{}})
    {:ok, scene} = Scenes.create_scene(%{name: "Evening", area_id: area.id})

    {:ok, view, _html} = live(conn, "/areas")

    assert has_element?(
             view,
             "#area-#{area.id} button[phx-click='delete_scene'][phx-value-id='#{scene.id}'][data-confirm]"
           )

    view
    |> element("#area-#{area.id} button[phx-click='delete_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    refute Scenes.get_scene(scene.id)
    refute render(view) =~ "Evening"
  end

  test "area actions ignore malformed ids without crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/areas")
    ref = Process.monitor(view.pid)

    render_click(view, "open_edit", %{"id" => "not-an-id"})
    render_click(view, "delete_scene", %{"id" => "not-an-id"})
    render_click(view, "delete_area", %{"id" => "not-an-id"})

    refute_received {:DOWN, ^ref, :process, _pid, _reason}
    assert render(view) =~ "Areas"
  end
end
