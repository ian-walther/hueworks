defmodule HueworksWeb.Api.AreasController do
  use Phoenix.Controller

  alias Hueworks.Api
  alias HueworksWeb.Api.Response

  def index(conn, _params) do
    Response.ok(conn, %{areas: Api.areas()})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, area_id} <- parse_id(id),
         {:ok, area} <- Api.area(area_id) do
      Response.ok(conn, area)
    else
      {:error, :invalid_id} ->
        Response.error(conn, 400, "invalid_parameter", "Area ID must be an integer.")

      {:error, :not_found} ->
        Response.error(conn, 404, "not_found", "Area not found.")
    end
  end

  def debug(conn, %{"id" => id}) do
    with {:ok, area_id} <- parse_id(id),
         {:ok, area} <- Api.debug_area(area_id) do
      Response.ok(conn, area)
    else
      {:error, :invalid_id} ->
        Response.error(conn, 400, "invalid_parameter", "Area ID must be an integer.")

      {:error, :not_found} ->
        Response.error(conn, 404, "not_found", "Area not found.")
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_id}
    end
  end
end
