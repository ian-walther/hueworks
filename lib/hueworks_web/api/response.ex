defmodule HueworksWeb.Api.Response do
  @moduledoc false

  import Plug.Conn

  def ok(conn, body, status \\ 200) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(body)
  end

  def error(conn, status, code, message, details \\ nil) do
    error = %{code: code, message: message}
    error = if is_nil(details), do: error, else: Map.put(error, :details, details)

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: error})
  end
end
