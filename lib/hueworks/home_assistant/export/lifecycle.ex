defmodule Hueworks.HomeAssistant.Export.Lifecycle do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.HomeAssistant.Export.Sync

  def configure(state, config, client_id, publish_fun)
      when is_map(state) and is_map(config) and is_binary(client_id) and is_function(publish_fun, 3) do
    state = maybe_unpublish_removed_entities(state, config, publish_fun)

    cond do
      not Runtime.export_enabled?(config) ->
        state
        |> publish_availability_if_connected("offline", publish_fun)
        |> stop_connection()
        |> Map.put(:config, config)

      Runtime.same_config?(state.config, config) and Connection.alive?(state.connection_pid) ->
        %{state | config: config}

      true ->
        state
        |> publish_availability_if_connected("offline", publish_fun)
        |> stop_connection()
        |> start_connection(config, client_id)
    end
  end

  def handle_cast(message, state, publish_fun)
      when is_map(state) and is_function(publish_fun, 3) do
    case sync_operation(message) do
      {function_name, extra_args} ->
        run_sync(state, function_name, extra_args, publish_fun)

      nil ->
        state
    end
  end

  def handle_connected(connection_client_id, state, client_id, publish_fun)
      when is_binary(connection_client_id) and is_map(state) and is_binary(client_id) and
             is_function(publish_fun, 3) do
    if connection_client_id == client_id and Runtime.export_enabled?(state.config) do
      :ok = publish_fun.(Hueworks.HomeAssistant.Export.availability_topic(), "online", retain: true)
      run_sync(state, :publish_all_entities, [], publish_fun)
    else
      state
    end
  end

  def handle_control_state(kind, id, state, publish_fun)
      when kind in [:light, :group] and is_integer(id) and is_map(state) and
             is_function(publish_fun, 3) do
    if Runtime.export_enabled?(state.config) and Runtime.lights_enabled?(state.config) and
         Connection.alive?(state.connection_pid) do
      run_sync(state, :publish_entity, [kind, id], publish_fun)
    else
      state
    end
  end

  defp maybe_unpublish_removed_entities(%{config: previous} = state, config, publish_fun) do
    cond do
      not Connection.alive?(state.connection_pid) ->
        state

      not is_map(previous) ->
        state

      true ->
        if Runtime.scenes_enabled?(previous) and not Runtime.scenes_enabled?(config) do
          Sync.unpublish_all_scenes(publish_fun, previous)
        end

        if Runtime.room_selects_enabled?(previous) and
             not Runtime.room_selects_enabled?(config) do
          Sync.unpublish_all_room_selects(publish_fun, previous)
        end

        if Runtime.lights_enabled?(previous) and not Runtime.lights_enabled?(config) do
          Sync.unpublish_all_light_entities(publish_fun, previous)
        end

        state
    end
  end

  defp start_connection(state, config, client_id) do
    case Connection.start(client_id, self(), config, Runtime.command_topic_filters()) do
      {:ok, pid} ->
        %{state | config: config, connection_pid: pid}

      {:error, reason} ->
        _ = reason
        %{state | config: config, connection_pid: nil}
    end
  end

  defp stop_connection(%{connection_pid: nil} = state), do: %{state | connection_pid: nil}

  defp stop_connection(%{connection_pid: pid} = state) do
    _ = Connection.stop(pid)
    %{state | connection_pid: nil}
  end

  defp publish_availability_if_connected(state, value, publish_fun) do
    if Connection.alive?(state.connection_pid) do
      :ok = publish_fun.(Hueworks.HomeAssistant.Export.availability_topic(), value, retain: true)
    end

    state
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
