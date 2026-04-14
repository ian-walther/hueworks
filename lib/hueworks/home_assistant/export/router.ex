defmodule Hueworks.HomeAssistant.Export.Router do
  @moduledoc false

  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeAssistant.Export.Commands
  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Scenes
  alias Hueworks.Schemas.Scene

  def dispatch(topic_levels, payload, config, publish_fun)
      when is_list(topic_levels) and is_function(publish_fun, 3) do
    normalized_payload = Hueworks.HomeAssistant.Export.Runtime.normalize_payload(payload)

    case {Messages.command_scene_id(topic_levels), Messages.command_room_id(topic_levels),
          Messages.command_export_target(topic_levels), normalized_payload} do
      {scene_id, _room_id, _entity_command, "ON"} when is_integer(scene_id) ->
        activate_scene(scene_id)

      {_scene_id, room_id, _entity_command, option_label} when is_integer(room_id) ->
        handle_room_select_command(room_id, option_label)

      {_scene_id, _room_id, %{kind: kind, id: id, mode: :switch}, command_payload} ->
        handle_switch_command(kind, id, command_payload, config, publish_fun)

      {_scene_id, _room_id, %{kind: kind, id: id, mode: :light}, command_payload} ->
        handle_light_command(kind, id, command_payload, config, publish_fun)

      _ ->
        :ok
    end
  end

  defp activate_scene(scene_id) do
    case Scenes.activate_scene(scene_id, trace: %{source: :home_assistant_mqtt_export}) do
      {:ok, _diff, _updated} ->
        :ok

      {:error, reason} ->
        Logger.warning("HA export scene activation failed: #{inspect(reason)}")
    end
  end

  defp handle_room_select_command(room_id, option_label)
       when is_integer(room_id) and option_label in ["Manual", "None", ""] do
    ActiveScenes.clear_for_room(room_id)
  end

  defp handle_room_select_command(room_id, option_label)
       when is_integer(room_id) and is_binary(option_label) do
    case Entities.scene_for_room_option(room_id, option_label) do
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

  defp handle_room_select_command(_room_id, _option_label), do: :ok

  defp handle_switch_command(kind, id, payload, config, publish_fun)
       when kind in [:light, :group] and is_integer(id) and is_binary(payload) do
    case Messages.normalize_power_payload(payload) do
      :on ->
        apply_power_command(kind, id, :on, config, publish_fun)

      :off ->
        apply_power_command(kind, id, :off, config, publish_fun)

      _ ->
        :ok
    end
  end

  defp handle_switch_command(_kind, _id, _payload, _config, _publish_fun), do: :ok

  defp handle_light_command(kind, id, payload, config, publish_fun)
       when kind in [:light, :group] and is_integer(id) do
    with entity when not is_nil(entity) <- Entities.fetch_entity(kind, id),
         {:ok, decoded} <- Commands.decode_json_payload(payload),
         {room_id, light_ids} when is_integer(room_id) and light_ids != [] <-
           Entities.control_target(kind, id),
         {:ok, action} <- Commands.normalize_light_command(decoded, entity) do
      case action do
        {:power, power} ->
          case ManualControl.apply_power_action(room_id, light_ids, power) do
            {:ok, _diff} ->
              publish_optimistic_power_state(kind, entity, power, config, publish_fun)
              :ok

            {:error, reason} ->
              Logger.warning("HA export power command failed: #{inspect(reason)}")
          end

        {:set_state, attrs} ->
          case ManualControl.apply_updates(room_id, light_ids, attrs) do
            {:ok, _diff} ->
              publish_optimistic_light_state(kind, entity, attrs, config, publish_fun)
              :ok

            {:error, reason} ->
              Logger.warning("HA export light command failed: #{inspect(reason)}")
          end
      end
    else
      _ -> :ok
    end
  end

  defp apply_power_command(kind, id, power, config, publish_fun)
       when kind in [:light, :group] and power in [:on, :off] do
    case Entities.control_target(kind, id) do
      {room_id, light_ids} when is_integer(room_id) and light_ids != [] ->
        case ManualControl.apply_power_action(room_id, light_ids, power) do
          {:ok, _diff} ->
            if entity = Entities.fetch_entity(kind, id) do
              publish_optimistic_power_state(kind, entity, power, config, publish_fun)
            end

            :ok

          {:error, reason} ->
            Logger.warning("HA export switch command failed: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  end

  defp publish_optimistic_power_state(kind, entity, power, _config, publish_fun)
       when kind in [:light, :group] and is_map(entity) do
    optimistic_state = Commands.optimistic_power_state(kind, entity, power)
    Publisher.publish_optimistic_entity_state(publish_fun, kind, entity, optimistic_state)
  end

  defp publish_optimistic_light_state(kind, entity, attrs, _config, publish_fun)
       when kind in [:light, :group] and is_map(entity) and is_map(attrs) do
    optimistic_state = Commands.optimistic_light_state(kind, entity, attrs)
    Publisher.publish_optimistic_entity_state(publish_fun, kind, entity, optimistic_state)
  end
end
