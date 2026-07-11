defmodule HueworksWeb.Api.EntitiesController do
  use Phoenix.Controller

  alias Hueworks.Api
  alias HueworksWeb.Api.Response

  def show_light(conn, %{"id" => id}), do: show_entity(conn, id, &Api.light/1, "Light")

  def show_group(conn, %{"id" => id}), do: show_entity(conn, id, &Api.group/1, "Group")

  def debug_light(conn, %{"id" => id}), do: show_entity(conn, id, &Api.debug_light/1, "Light")

  def debug_group(conn, %{"id" => id}), do: show_entity(conn, id, &Api.debug_group/1, "Group")

  defp show_entity(conn, id, fetch, label) do
    with {:ok, entity_id} <- parse_id(id),
         {:ok, entity} <- fetch.(entity_id) do
      Response.ok(conn, entity)
    else
      {:error, :invalid_id} ->
        Response.error(conn, 400, "invalid_parameter", "#{label} ID must be an integer.")

      {:error, :not_found} ->
        Response.error(conn, 404, "not_found", "#{label} not found.")
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_id}
    end
  end
end
