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
        get_entity_value(kind, id, Keyword.get(opts, :characteristic, :on))

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
        put_entity_value(kind, id, Keyword.get(opts, :characteristic, :on), value)

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

  defp get_entity_value(kind, id, :on) do
    {:ok, entity_on?(kind, id)}
  end

  defp get_entity_value(kind, id, :brightness) do
    {:ok, entity_brightness(kind, id)}
  end

  defp get_entity_value(_kind, _id, _characteristic) do
    {:error, "Unsupported HomeKit entity characteristic"}
  end

  defp entity_on?(kind, id) do
    case entity_state(kind, id) do
      %{power: :on} -> true
      _ -> false
    end
  end

  defp entity_brightness(kind, id) do
    case entity_state(kind, id) do
      %{brightness: brightness} when is_number(brightness) -> clamp_brightness(brightness)
      _ -> 100
    end
  end

  defp entity_state(kind, id), do: State.get(kind, id) || %{}

  defp scene_active?(scene_id) do
    with %Scene{} = scene <- Entities.fetch_scene(scene_id),
         %{scene_id: active_scene_id} <- ActiveScenes.get_for_area(scene.area_id) do
      active_scene_id == scene.id
    else
      _ -> false
    end
  end

  defp put_entity_value(kind, id, :on, value) do
    power = if value in [true, 1], do: :on, else: :off

    case Entities.control_target(kind, id) do
      {area_id, light_ids} when is_integer(area_id) and light_ids != [] ->
        case ManualControl.apply_power_action(area_id, light_ids, power) do
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

  defp put_entity_value(kind, id, :brightness, value) do
    brightness = clamp_brightness(value)

    case Entities.control_target(kind, id) do
      {area_id, light_ids} when is_integer(area_id) and light_ids != [] ->
        case ManualControl.apply_updates(area_id, light_ids, %{brightness: brightness}) do
          {:ok, _diff} ->
            :ok

          {:error, reason} ->
            Logger.warning("HomeKit #{kind} brightness command failed: #{inspect(reason)}")
            {:error, "HueWorks brightness command failed"}
        end

      _ ->
        {:error, "HueWorks entity is not controllable"}
    end
  end

  defp put_entity_value(_kind, _id, _characteristic, _value) do
    {:error, "Unsupported HomeKit entity characteristic"}
  end

  defp clamp_brightness(value) when is_number(value) do
    value
    |> round()
    |> max(0)
    |> min(100)
  end

  defp clamp_brightness(_value), do: 100

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
