defmodule Hueworks.HomeAssistant.Export.Lifecycle.ConfigTransition do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.HomeAssistant.Export.ServerState
  alias Hueworks.HomeAssistant.Export.Sync

  def configure(%ServerState{} = state, config, client_id, publish_fun)
      when is_map(config) and is_binary(client_id) and is_function(publish_fun, 3) do
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

  defp maybe_unpublish_removed_entities(%ServerState{config: previous} = state, config, publish_fun) do
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

  defp stop_connection(%ServerState{connection_pid: nil} = state), do: %{state | connection_pid: nil}

  defp stop_connection(%ServerState{connection_pid: pid} = state) do
    _ = Connection.stop(pid)
    %{state | connection_pid: nil}
  end

  defp publish_availability_if_connected(state, value, publish_fun) do
    if Connection.alive?(state.connection_pid) do
      :ok = publish_fun.(Hueworks.HomeAssistant.Export.availability_topic(), value, retain: true)
    end

    state
  end
end
