defmodule Hueworks.HomeAssistant.Export.Lifecycle.SyncDispatch do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Config
  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.ServerState
  alias Hueworks.HomeAssistant.Export.Sync

  def handle_cast(:refresh_all_scenes, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_all_entities(publish_fun, state.config)
    state
  end

  def handle_cast({:refresh_area, area_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_area_entities(publish_fun, area_id, state.config)
    state
  end

  def handle_cast({:refresh_area_select, area_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_area_select(publish_fun, area_id, state.config)
    state
  end

  def handle_cast({:refresh_light, light_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_entity(publish_fun, :light, light_id, state.config)
    state
  end

  def handle_cast({:refresh_group, group_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_entity(publish_fun, :group, group_id, state.config)
    state
  end

  def handle_cast({:refresh_presence_input, input_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_presence_input(publish_fun, input_id, state.config)
    state
  end

  def handle_cast(
        {:refresh_presence_inputs_for_area, area_id},
        %ServerState{} = state,
        publish_fun
      )
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_presence_inputs_for_area(publish_fun, area_id, state.config)
    state
  end

  def handle_cast({:refresh_scene, scene_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.publish_scene(publish_fun, scene_id, state.config)
    state
  end

  def handle_cast({:remove_light, light_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.unpublish_entity(publish_fun, :light, light_id, state.config)
    state
  end

  def handle_cast({:remove_group, group_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.unpublish_entity(publish_fun, :group, group_id, state.config)
    state
  end

  def handle_cast({:remove_presence_input, input_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.unpublish_presence_input(publish_fun, input_id, state.config)
    state
  end

  def handle_cast({:remove_scene, scene_id}, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3) do
    :ok = Sync.unpublish_scene(publish_fun, scene_id, state.config)
    state
  end

  def handle_cast(
        {:remove_area, area_id, identifier},
        %ServerState{} = state,
        publish_fun
      )
      when is_function(publish_fun, 3) do
    :ok = Sync.unpublish_area_select(publish_fun, area_id, identifier, state.config)
    state
  end

  def handle_cast(_message, %ServerState{} = state, publish_fun)
      when is_function(publish_fun, 3),
      do: state

  def handle_connected(connection_client_id, %ServerState{} = state, client_id, publish_fun)
      when is_binary(connection_client_id) and is_binary(client_id) and
             is_function(publish_fun, 3) do
    if connection_client_id == client_id and Config.export_enabled?(state.config) do
      :ok =
        publish_fun.(Messages.availability_topic(), "online", retain: true)

      :ok = Sync.publish_all_entities(publish_fun, state.config)
      state
    else
      state
    end
  end

  def handle_control_state(kind, id, %ServerState{} = state, publish_fun)
      when kind in [:light, :group] and is_integer(id) and
             is_function(publish_fun, 3) do
    if Config.export_enabled?(state.config) and Config.lights_enabled?(state.config) and
         Connection.alive?(state.connection_pid) do
      :ok = Sync.publish_entity(publish_fun, kind, id, state.config)

      if kind == :light do
        :ok = Sync.publish_groups_for_light(publish_fun, id, state.config)
      end

      state
    else
      state
    end
  end
end
