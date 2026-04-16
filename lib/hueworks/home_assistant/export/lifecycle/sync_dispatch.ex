defmodule Hueworks.HomeAssistant.Export.Lifecycle.SyncDispatch do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.HomeAssistant.Export.ServerState
  alias Hueworks.HomeAssistant.Export.Sync

  def handle_cast(message, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    case sync_operation(message) do
      {function_name, extra_args} ->
        run_sync(state, function_name, extra_args, publish_fun)

      nil ->
        state
    end
  end

  def handle_connected(connection_client_id, %ServerState{} = state, client_id, publish_fun)
      when is_binary(connection_client_id) and is_binary(client_id) and
             is_function(publish_fun, 3) do
    if connection_client_id == client_id and Runtime.export_enabled?(state.config) do
      :ok = publish_fun.(Hueworks.HomeAssistant.Export.availability_topic(), "online", retain: true)
      run_sync(state, :publish_all_entities, [], publish_fun)
    else
      state
    end
  end

  def handle_control_state(kind, id, %ServerState{} = state, publish_fun)
      when kind in [:light, :group] and is_integer(id) and
             is_function(publish_fun, 3) do
    if Runtime.export_enabled?(state.config) and Runtime.lights_enabled?(state.config) and
         Connection.alive?(state.connection_pid) do
      run_sync(state, :publish_entity, [kind, id], publish_fun)
    else
      state
    end
  end

  defp run_sync(state, function_name, extra_args, publish_fun) when is_list(extra_args) do
    :ok = apply(Sync, function_name, [publish_fun | extra_args] ++ [state.config])
    state
  end

  defp sync_operation(:refresh_all_scenes), do: {:publish_all_entities, []}
  defp sync_operation({:refresh_room, room_id}), do: {:publish_room_entities, [room_id]}
  defp sync_operation({:refresh_room_select, room_id}), do: {:publish_room_select, [room_id]}
  defp sync_operation({:refresh_light, light_id}), do: {:publish_entity, [:light, light_id]}
  defp sync_operation({:refresh_group, group_id}), do: {:publish_entity, [:group, group_id]}
  defp sync_operation({:refresh_scene, scene_id}), do: {:publish_scene, [scene_id]}
  defp sync_operation({:remove_light, light_id}), do: {:unpublish_entity, [:light, light_id]}
  defp sync_operation({:remove_group, group_id}), do: {:unpublish_entity, [:group, group_id]}
  defp sync_operation({:remove_scene, scene_id}), do: {:unpublish_scene, [scene_id]}
  defp sync_operation({:remove_room, room_id}), do: {:unpublish_room_select, [room_id]}
  defp sync_operation(_message), do: nil
end
