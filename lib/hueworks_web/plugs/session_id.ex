defmodule HueworksWeb.Plugs.SessionId do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "filter_session_id") do
      nil ->
        put_session(conn, "filter_session_id", Ecto.UUID.generate())

      _ ->
        conn
    end
  end
end
