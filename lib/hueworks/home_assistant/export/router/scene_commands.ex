defmodule Hueworks.HomeAssistant.Export.Router.SceneCommands do
  @moduledoc false

  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.Scenes
  alias Hueworks.Schemas.Scene

  def activate_scene(scene_id) when is_integer(scene_id) do
    case Scenes.activate_scene(scene_id, trace: %{source: :home_assistant_mqtt_export}) do
      {:ok, _diff, _updated} ->
        :ok

      {:error, reason} ->
        Logger.warning("HA export scene activation failed: #{inspect(reason)}")
    end
  end

  def activate_scene(_scene_id), do: :ok

  def handle_room_select_command(room_id, option_label)
      when is_integer(room_id) and option_label in ["Manual", "None", ""] do
    ActiveScenes.clear_for_room(room_id)
  end

  def handle_room_select_command(room_id, option_label)
      when is_integer(room_id) and is_binary(option_label) do
    room_id
    |> Entities.scene_for_room_option(option_label)
    |> case do
      %Scene{} = scene ->
        case Scenes.activate_scene(scene.id, trace: %{source: :home_assistant_mqtt_export_select}) do
          {:ok, _diff, _updated} ->
            :ok

          {:error, reason} ->
            Logger.warning("HA export room select activation failed: #{inspect(reason)}")
        end

      nil ->
        :ok
    end
  end

  def handle_room_select_command(_room_id, _option_label), do: :ok
end
