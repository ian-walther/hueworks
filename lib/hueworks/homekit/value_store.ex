defmodule Hueworks.HomeKit.ValueStore do
  @moduledoc false

  @behaviour HAP.ValueStore

  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.State
  alias Hueworks.HomeKit
  alias Hueworks.HomeKit.Entities
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Scenes
  alias Hueworks.Schemas.Scene

  @impl true
  def get_value(opts) do
    case {Keyword.get(opts, :kind), Keyword.get(opts, :id)} do
      {kind, id} when kind in [:light, :group] and is_integer(id) ->
        {:ok, entity_on?(kind, id)}

      {:scene, id} when is_integer(id) ->
        {:ok, scene_active?(id)}

      _ ->
        {:error, "Invalid HomeKit value-store target"}
    end
  end

  @impl true
  def put_value(value, opts) do
    case {Keyword.get(opts, :kind), Keyword.get(opts, :id)} do
      {kind, id} when kind in [:light, :group] and is_integer(id) ->
        put_entity_value(kind, id, value)

      {:scene, id} when is_integer(id) ->
        put_scene_value(id, value)

      _ ->
        {:error, "Invalid HomeKit value-store target"}
    end
  end

  @impl true
  def set_change_token(change_token, opts) do
    HomeKit.put_change_token(opts, change_token)
    :ok
  end

  defp entity_on?(kind, id) do
    case State.get(kind, id) || %{} do
      %{power: :on} -> true
      %{"power" => "on"} -> true
      %{"power" => :on} -> true
      _ -> false
    end
  end

  defp scene_active?(scene_id) do
    with %Scene{} = scene <- Entities.fetch_scene(scene_id),
         %{scene_id: active_scene_id} <- ActiveScenes.get_for_room(scene.room_id) do
      active_scene_id == scene.id
    else
      _ -> false
    end
  end

  defp put_entity_value(kind, id, value) do
    power = if value in [true, 1], do: :on, else: :off

    case Entities.control_target(kind, id) do
      {room_id, light_ids} when is_integer(room_id) and light_ids != [] ->
        case ManualControl.apply_power_action(room_id, light_ids, power) do
          {:ok, _result} ->
            :ok

          {:error, reason} ->
            Logger.warning("HomeKit #{kind} command failed: #{inspect(reason)}")
            {:error, "HueWorks command failed"}
        end

      _ ->
        {:error, "HueWorks entity is not controllable"}
    end
  end

  defp put_scene_value(scene_id, value) when value in [true, 1] do
    case Scenes.activate_scene(scene_id, trace: %{source: :homekit}) do
      {:ok, _diff, _updated} ->
        :ok

      {:error, reason} ->
        Logger.warning("HomeKit scene activation failed: #{inspect(reason)}")
        {:error, "HueWorks scene activation failed"}
    end
  end

  defp put_scene_value(scene_id, _value) do
    ActiveScenes.deactivate_scene(scene_id)
    :ok
  end
end
