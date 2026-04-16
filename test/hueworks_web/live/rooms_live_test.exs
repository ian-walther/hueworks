defmodule HueworksWeb.RoomsLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Schemas.Room
  alias Hueworks.Scenes

  test "rooms page renders existing rooms", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Studio", metadata: %{}})

    {:ok, _view, html} = live(conn, "/rooms")

    assert html =~ "Rooms"
    assert html =~ "Studio"
    assert html =~ "room-#{room.id}"
  end

  test "rooms page creates a room through the modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/rooms")

    render_click(element(view, "button[phx-click='open_new']"))

    html =
      view
      |> form("form[phx-submit='save_room']", %{"name" => "Guest Room"})
      |> render_submit()

    assert html =~ "Guest Room"

    room = Repo.get_by!(Room, name: "Guest Room")
    assert room.display_name == nil
  end

  test "rooms page updates a room display name through the modal", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Studio", metadata: %{}})

    {:ok, view, _html} = live(conn, "/rooms")

    render_click(element(view, "#room-#{room.id} button[phx-click='open_edit']"))

    html =
      view
      |> form("form[phx-submit='save_room']", %{"name" => "Creative Studio"})
      |> render_submit()

    assert html =~ "Creative Studio"

    updated = Repo.get!(Room, room.id)
    assert updated.display_name == "Creative Studio"
  end

  test "rooms page deletes a room", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Guest Room", metadata: %{}})

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} button[phx-click='delete_room']")
    |> render_click()

    refute Repo.get(Room, room.id)
    refute render(view) =~ "Guest Room"
  end

  test "rooms page deletes a scene from the room card", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Studio", metadata: %{}})
    {:ok, scene} = Scenes.create_scene(%{name: "Evening", room_id: room.id})

    {:ok, view, _html} = live(conn, "/rooms")

    view
    |> element("#room-#{room.id} button[phx-click='delete_scene'][phx-value-id='#{scene.id}']")
    |> render_click()

    refute Scenes.get_scene(scene.id)
    refute render(view) =~ "Evening"
  end
end
