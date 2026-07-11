defmodule HueworksWeb.Api.TracesController do
  use Phoenix.Controller

  alias Hueworks.Api
  alias HueworksWeb.Api.Response

  def index(conn, params) do
    case parse_filters(params) do
      {:ok, filters} ->
        Response.ok(conn, Api.traces(filters))

      {:error, details} ->
        Response.error(conn, 400, "invalid_parameter", "Invalid trace filter.", details)
    end
  end

  defp parse_filters(params) do
    with {:ok, limit} <- optional_integer(params, "limit", 1..100),
         {:ok, room_id} <- optional_integer(params, "room_id", 1..2_147_483_647),
         {:ok, entity_id} <- optional_integer(params, "entity_id", 1..2_147_483_647),
         {:ok, entity_kind} <- optional_entity_kind(params["entity_kind"]),
         {:ok, trace_id} <- optional_string(params["trace_id"]),
         {:ok, source} <- optional_string(params["source"]) do
      filters =
        [
          limit: limit,
          room_id: room_id,
          entity_id: entity_id,
          entity_kind: entity_kind,
          trace_id: trace_id,
          source: source
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, filters}
    end
  end

  defp optional_integer(params, key, range) do
    case Map.get(params, key) do
      nil -> {:ok, nil}
      value when is_integer(value) -> validate_integer(value, range, key)
      value when is_binary(value) -> parse_integer(value, range, key)
      _ -> {:error, %{parameter: key}}
    end
  end

  defp parse_integer(value, range, key) do
    case Integer.parse(value) do
      {parsed, ""} -> validate_integer(parsed, range, key)
      _ -> {:error, %{parameter: key}}
    end
  end

  defp validate_integer(value, range, key) do
    if value >= range.first and value <= range.last do
      {:ok, value}
    else
      {:error, %{parameter: key}}
    end
  end

  defp optional_entity_kind(nil), do: {:ok, nil}
  defp optional_entity_kind("light"), do: {:ok, :light}
  defp optional_entity_kind("group"), do: {:ok, :group}
  defp optional_entity_kind(_), do: {:error, %{parameter: "entity_kind"}}

  defp optional_string(nil), do: {:ok, nil}

  defp optional_string(value) when is_binary(value) and byte_size(value) in 1..200,
    do: {:ok, value}

  defp optional_string(_), do: {:error, %{parameter: "filter"}}
end
