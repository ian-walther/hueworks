defmodule HueworksWeb.Plugs.SessionIdTest do
  use HueworksWeb.ConnCase, async: true

  test "sets filter session id in session and response cookie", %{conn: conn} do
    conn = get(conn, "/lights")

    assert is_binary(get_session(conn, "filter_session_id"))

    assert conn.resp_cookies["hw_filter_session_id"].value ==
             get_session(conn, "filter_session_id")
  end

  test "reuses request cookie value as filter session id", %{conn: conn} do
    existing = Ecto.UUID.generate()

    conn =
      conn
      |> Plug.Conn.put_req_header("cookie", "hw_filter_session_id=#{existing}")
      |> get("/lights")

    assert get_session(conn, "filter_session_id") == existing
    assert conn.resp_cookies["hw_filter_session_id"].value == existing
  end
end
