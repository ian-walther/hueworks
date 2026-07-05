defmodule HueworksWeb.SecurityPostureTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "trusted-LAN clients intentionally access LiveViews without authentication", %{conn: conn} do
    assert conn.req_headers == []
    assert {:ok, _view, html} = live(conn, "/rooms")
    assert html =~ "Rooms"
  end
end
