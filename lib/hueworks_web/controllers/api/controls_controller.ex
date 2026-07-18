defmodule HueworksWeb.Api.ControlsController do
  use Phoenix.Controller

  alias Hueworks.Api
  alias HueworksWeb.Api.Response

  def activate_scene(conn, %{"id" => id}) do
    with {:ok, scene_id} <- parse_id(id),
         {:ok, result} <- Api.activate_scene(scene_id) do
      Response.ok(conn, result)
    else
      error -> control_error(conn, error, "Scene")
    end
  end

  def deactivate_area_scene(conn, %{"id" => id}) do
    with {:ok, area_id} <- parse_id(id),
         {:ok, result} <- Api.deactivate_area_scene(area_id) do
      Response.ok(conn, result)
    else
      error -> control_error(conn, error, "Area")
    end
  end

  def control_light(conn, %{"id" => id} = params) do
    control_entity(conn, :light, id, params)
  end

  def control_group(conn, %{"id" => id} = params) do
    control_entity(conn, :group, id, params)
  end

  def refresh_physical_state(conn, _params) do
    case Api.refresh_physical_state() do
      {:ok, result} -> Response.ok(conn, result, 202)
      error -> control_error(conn, error, "Control runtime")
    end
  end

  defp control_entity(conn, kind, id, params) do
    with {:ok, entity_id} <- parse_id(id),
         {:ok, result} <- Api.control_entity(kind, entity_id, Map.drop(params, ["id"])) do
      Response.ok(conn, result)
    else
      error -> control_error(conn, error, kind |> Atom.to_string() |> String.capitalize())
    end
  end

  defp control_error(conn, {:error, :invalid_id}, label) do
    Response.error(conn, 400, "invalid_parameter", "#{label} ID must be an integer.")
  end

  defp control_error(conn, {:error, :not_found}, label) do
    Response.error(conn, 404, "not_found", "#{label} not found or is not controllable.")
  end

  defp control_error(conn, {:error, :scene_active_manual_adjustment_not_allowed}, _label) do
    Response.error(
      conn,
      409,
      "scene_active_manual_adjustment_not_allowed",
      "Brightness, temperature, and color are read-only while a scene is active."
    )
  end

  defp control_error(conn, {:error, :unsupported_capability}, _label) do
    Response.error(
      conn,
      422,
      "unsupported_capability",
      "The target does not support that control."
    )
  end

  defp control_error(conn, {:error, :invalid_control}, _label) do
    Response.error(conn, 422, "invalid_control", "Provide exactly one valid control value.")
  end

  defp control_error(conn, {:error, :no_members}, _label) do
    Response.error(conn, 422, "no_members", "The group has no direct member lights.")
  end

  defp control_error(conn, _error, _label) do
    Response.error(conn, 503, "control_unavailable", "The control runtime is unavailable.")
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_id}
    end
  end
end
