defmodule HueworksWeb.Api.EntitiesController do
  use Phoenix.Controller

  alias Hueworks.Api
  alias HueworksWeb.Api.Response

  def show_light(conn, %{"id" => id}), do: show_entity(conn, id, &Api.light/1, "Light")

  def show_group(conn, %{"id" => id}), do: show_entity(conn, id, &Api.group/1, "Group")

  def search(conn, params) do
    with {:ok, query} <- parse_query(params["query"]),
         {:ok, kind} <- parse_kind(params["kind"]),
         {:ok, area_id} <- parse_optional_id(params["area_id"], "area_id"),
         {:ok, limit} <- parse_optional_limit(params["limit"]) do
      filters =
        [kind: kind, area_id: area_id, limit: limit]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      Response.ok(conn, Api.search_entities(query, filters))
    else
      {:error, parameter} ->
        Response.error(conn, 400, "invalid_parameter", "Invalid entity search parameter.", %{
          parameter: parameter
        })
    end
  end

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

  defp parse_query(value) when is_binary(value) do
    query = String.trim(value)

    if byte_size(query) in 1..120 do
      {:ok, query}
    else
      {:error, "query"}
    end
  end

  defp parse_query(_value), do: {:error, "query"}

  defp parse_kind(nil), do: {:ok, nil}
  defp parse_kind("light"), do: {:ok, :light}
  defp parse_kind("group"), do: {:ok, :group}
  defp parse_kind(_value), do: {:error, "kind"}

  defp parse_optional_id(nil, _parameter), do: {:ok, nil}

  defp parse_optional_id(value, parameter) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, parameter}
    end
  end

  defp parse_optional_id(_value, parameter), do: {:error, parameter}

  defp parse_optional_limit(nil), do: {:ok, nil}

  defp parse_optional_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..100 -> {:ok, limit}
      _ -> {:error, "limit"}
    end
  end

  defp parse_optional_limit(_value), do: {:error, "limit"}
end
