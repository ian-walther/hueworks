defmodule HueworksWeb.Api.RoomsController do
  use Phoenix.Controller

  alias Hueworks.Api
  alias HueworksWeb.Api.Response

  def index(conn, _params) do
    Response.ok(conn, %{rooms: Api.rooms()})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, room_id} <- parse_id(id),
         {:ok, room} <- Api.room(room_id) do
      Response.ok(conn, room)
    else
      {:error, :invalid_id} ->
        Response.error(conn, 400, "invalid_parameter", "Room ID must be an integer.")

      {:error, :not_found} ->
        Response.error(conn, 404, "not_found", "Room not found.")
    end
  end

  def debug(conn, %{"id" => id}) do
    with {:ok, room_id} <- parse_id(id),
         {:ok, room} <- Api.debug_room(room_id) do
      Response.ok(conn, room)
    else
      {:error, :invalid_id} ->
        Response.error(conn, 400, "invalid_parameter", "Room ID must be an integer.")

      {:error, :not_found} ->
        Response.error(conn, 404, "not_found", "Room not found.")
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_id}
    end
  end
end
