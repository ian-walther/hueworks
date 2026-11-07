defmodule Hueworks.HomeAssistant.Export.Lifecycle.ConfigTransition do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.Config
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.ServerState
  alias Hueworks.HomeAssistant.Export.Sync

  def configure(%ServerState{} = state, config, client_id, publish_fun)
      when is_map(config) and is_binary(client_id) and is_function(publish_fun, 3) do
    state = maybe_unpublish_removed_entities(state, config, publish_fun)

    cond do
      not Config.export_enabled?(config) ->
        state
        |> publish_availability_if_connected("offline", publish_fun)
        |> stop_connection()
        |> Map.put(:config, config)

      Config.same_config?(state.config, config) and Connection.alive?(state.connection_pid) ->
        %{state | config: config}

      true ->
        state
        |> publish_availability_if_connected("offline", publish_fun)
        |> stop_connection()
        |> start_connection(config, client_id)
    end
  end

  defp maybe_unpublish_removed_entities(
         %ServerState{config: previous} = state,
         config,
         publish_fun
       ) do
    if Connection.alive?(state.connection_pid) and is_map(previous) do
      unpublish_removed_entities(previous, config, publish_fun)
    end

    state
  end

  defp unpublish_removed_entities(previous, config, publish_fun) do
    [
      {&Config.scenes_enabled?/1, &Sync.unpublish_all_scenes/2},
      {&Config.area_selects_enabled?/1, &Sync.unpublish_all_area_selects/2},
      {&Config.lights_enabled?/1, &Sync.unpublish_all_light_entities/2},
      {&Config.export_enabled?/1, &Sync.unpublish_settings/2}
    ]
    |> Enum.each(fn {enabled?, unpublish} ->
      if enabled?.(previous) and not enabled?.(config), do: unpublish.(publish_fun, previous)
    end)
  end

  defp start_connection(state, config, client_id) do
    case Connection.start(client_id, self(), config, Config.command_topic_filters()) do
      {:ok, pid} ->
        %{state | config: config, connection_pid: pid}

      {:error, reason} ->
        _ = reason
        %{state | config: config, connection_pid: nil}
    end
  end

  defp stop_connection(%ServerState{connection_pid: nil} = state),
    do: %{state | settings_session: nil}

  defp stop_connection(%ServerState{connection_pid: pid} = state) do
    _ = Connection.stop(pid)
    %{state | connection_pid: nil, settings_session: nil}
  end

  defp publish_availability_if_connected(state, value, publish_fun) do
    if Connection.alive?(state.connection_pid) do
      :ok = publish_fun.(Messages.availability_topic(), value, retain: true)
    end

    state
  end
end
