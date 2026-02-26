defmodule HueworksWeb.Plugs.SessionId do
  @moduledoc false

  import Plug.Conn

  @cookie_key "hw_filter_session_id"
  @session_key "filter_session_id"
  @cookie_max_age 60 * 60 * 24 * 365

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    session_id =
      get_session(conn, @session_key) ||
        conn.req_cookies[@cookie_key] ||
        Ecto.UUID.generate()

    conn
    |> put_session(@session_key, session_id)
    |> put_resp_cookie(@cookie_key, session_id,
      max_age: @cookie_max_age,
      http_only: true,
      same_site: "Lax"
    )
  end
end
