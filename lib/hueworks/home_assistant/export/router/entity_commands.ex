defmodule Hueworks.HomeAssistant.Export.Router.EntityCommands do
  @moduledoc false

  require Logger

  alias Hueworks.HomeAssistant.Export.Commands
  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.Lights.ManualControl

  def handle_switch_command(kind, id, payload, config, publish_fun)
      when kind in [:light, :group] and is_integer(id) and is_binary(payload) and
             is_function(publish_fun, 3) do
    case Messages.normalize_power_payload(payload) do
      :on ->
        apply_power_command(kind, id, :on, config, publish_fun)

      :off ->
        apply_power_command(kind, id, :off, config, publish_fun)

      _ ->
        :ok
    end
  end

  def handle_switch_command(_kind, _id, _payload, _config, _publish_fun), do: :ok

  def handle_light_command(kind, id, payload, config, publish_fun)
      when kind in [:light, :group] and is_integer(id) and is_function(publish_fun, 3) do
    with entity when not is_nil(entity) <- Entities.fetch_entity(kind, id),
         {:ok, decoded} <- Commands.decode_json_payload(payload),
         {room_id, light_ids} when is_integer(room_id) and light_ids != [] <-
           Entities.control_target(kind, id),
         {:ok, action} <- Commands.normalize_light_command(decoded, entity) do
      dispatch_light_action(action, kind, entity, room_id, light_ids, config, publish_fun)
    else
      _ -> :ok
    end
  end

  def handle_light_command(_kind, _id, _payload, _config, _publish_fun), do: :ok

  defp dispatch_light_action(
         {:power, power},
         kind,
         entity,
         room_id,
         light_ids,
         _config,
         publish_fun
       ) do
    case ManualControl.apply_power_action(room_id, light_ids, power) do
      {:ok, _diff} ->
        publish_optimistic_power_state(kind, entity, power, publish_fun)
        :ok

      {:error, reason} ->
        Logger.warning("HA export power command failed: #{inspect(reason)}")
    end
  end

  defp dispatch_light_action(
         {:set_state, attrs},
         kind,
         entity,
         room_id,
         light_ids,
         _config,
         publish_fun
       ) do
    case ManualControl.apply_updates(room_id, light_ids, attrs) do
      {:ok, _diff} ->
        publish_optimistic_light_state(kind, entity, attrs, publish_fun)
        :ok

      {:error, reason} ->
        Logger.warning("HA export light command failed: #{inspect(reason)}")
    end
  end

  defp apply_power_command(kind, id, power, _config, publish_fun)
       when kind in [:light, :group] and power in [:on, :off] and is_function(publish_fun, 3) do
    kind
    |> Entities.control_target(id)
    |> case do
      {room_id, light_ids} when is_integer(room_id) and light_ids != [] ->
        case ManualControl.apply_power_action(room_id, light_ids, power) do
          {:ok, _diff} ->
            if entity = Entities.fetch_entity(kind, id) do
              publish_optimistic_power_state(kind, entity, power, publish_fun)
            end

            :ok

          {:error, reason} ->
            Logger.warning("HA export switch command failed: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  end

  defp publish_optimistic_power_state(kind, entity, power, publish_fun)
       when kind in [:light, :group] and is_map(entity) and is_function(publish_fun, 3) do
    kind
    |> Commands.optimistic_power_state(entity, power)
    |> then(&Publisher.publish_optimistic_entity_state(publish_fun, kind, entity, &1))
  end

  defp publish_optimistic_light_state(kind, entity, attrs, publish_fun)
       when kind in [:light, :group] and is_map(entity) and is_map(attrs) and
              is_function(publish_fun, 3) do
    kind
    |> Commands.optimistic_light_state(entity, attrs)
    |> then(&Publisher.publish_optimistic_entity_state(publish_fun, kind, entity, &1))
  end
end
