defmodule Hueworks.HomeAssistant.Export do
  @moduledoc false

  use GenServer

  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Router
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.HomeAssistant.Export.Sync
  alias Hueworks.Instance
  alias Hueworks.Schemas.{Group, Light, Scene}
  alias Phoenix.PubSub

  @default_discovery_prefix "homeassistant"
  @default_topic_prefix "hueworks/ha_export"

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def reload do
    maybe_cast(:reload)
  end

  def refresh_all_scenes do
    maybe_cast(:refresh_all_scenes)
  end

  def refresh_room(room_id) when is_integer(room_id) do
    maybe_cast({:refresh_room, room_id})
  end

  def refresh_room_select(room_id) when is_integer(room_id) do
    maybe_cast({:refresh_room_select, room_id})
  end

  def refresh_light(%Light{id: light_id}), do: refresh_light(light_id)

  def refresh_light(light_id) when is_integer(light_id) do
    maybe_cast({:refresh_light, light_id})
  end

  def refresh_group(%Group{id: group_id}), do: refresh_group(group_id)

  def refresh_group(group_id) when is_integer(group_id) do
    maybe_cast({:refresh_group, group_id})
  end

  def remove_light(%Light{id: light_id}), do: remove_light(light_id)

  def remove_light(light_id) when is_integer(light_id) do
    maybe_cast({:remove_light, light_id})
  end

  def remove_group(%Group{id: group_id}), do: remove_group(group_id)

  def remove_group(group_id) when is_integer(group_id) do
    maybe_cast({:remove_group, group_id})
  end

  def refresh_scene(%Scene{id: scene_id}), do: refresh_scene(scene_id)

  def refresh_scene(scene_id) when is_integer(scene_id) do
    maybe_cast({:refresh_scene, scene_id})
  end

  def remove_scene(%Scene{id: scene_id}), do: remove_scene(scene_id)

  def remove_scene(scene_id) when is_integer(scene_id) do
    maybe_cast({:remove_scene, scene_id})
  end

  def remove_room(room_id) when is_integer(room_id) do
    maybe_cast({:remove_room, room_id})
  end

  def client_id do
    "hwhaexp-#{Instance.slug()}"
  end

  defdelegate availability_topic(), to: Messages
  defdelegate command_topic(scene_id), to: Messages
  defdelegate attributes_topic(scene_id), to: Messages
  defdelegate room_select_command_topic(room_id), to: Messages
  defdelegate room_select_state_topic(room_id), to: Messages
  defdelegate room_select_attributes_topic(room_id), to: Messages
  defdelegate entity_attributes_topic(kind, id), to: Messages
  defdelegate switch_command_topic(kind, id), to: Messages
  defdelegate switch_state_topic(kind, id), to: Messages
  defdelegate light_command_topic(kind, id), to: Messages
  defdelegate light_state_topic(kind, id), to: Messages

  def discovery_topic(scene_id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.discovery_topic(scene_id, discovery_prefix)

  def room_select_discovery_topic(room_id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.room_select_discovery_topic(room_id, discovery_prefix)

  def switch_discovery_topic(kind, id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.switch_discovery_topic(kind, id, discovery_prefix)

  def light_discovery_topic(kind, id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.light_discovery_topic(kind, id, discovery_prefix)

  def command_scene_id(topic_levels, topic_prefix \\ @default_topic_prefix),
    do: Messages.command_scene_id(topic_levels, topic_prefix)

  def command_room_id(topic_levels, topic_prefix \\ @default_topic_prefix),
    do: Messages.command_room_id(topic_levels, topic_prefix)

  def discovery_payload(scene, config \\ export_config()),
    do: Messages.discovery_payload(scene, config)

  defdelegate scene_attributes_payload(scene), to: Messages

  def room_select_discovery_payload(room, scenes, config \\ export_config()),
    do: Messages.room_select_discovery_payload(room, scenes, config)

  defdelegate room_select_attributes_payload(room, scenes), to: Messages

  def switch_discovery_payload(kind, entity, config \\ export_config()),
    do: Messages.switch_discovery_payload(kind, entity, config)

  def light_discovery_payload(kind, entity, config \\ export_config()),
    do: Messages.light_discovery_payload(kind, entity, config)

  defdelegate entity_attributes_payload(kind, entity), to: Messages

  def export_config do
    Runtime.export_config()
  end

  @impl true
  def init(_state) do
    PubSub.subscribe(Hueworks.PubSub, "control_state")
    {:ok, %{config: nil, connection_pid: nil}, {:continue, :configure}}
  end

  @impl true
  def handle_continue(:configure, state) do
    {:noreply, configure(state)}
  end

  @impl true
  def handle_cast(:reload, state) do
    {:noreply, configure(state)}
  end

  def handle_cast(message, state) do
    {:noreply, handle_export_cast(message, state)}
  end

  @impl true
  def handle_info({:mqtt_connected, connection_client_id}, %{config: config} = state) do
    if connection_client_id == client_id() and Runtime.export_enabled?(config) do
      :ok = publish_availability("online")
      {:noreply, run_sync(state, :publish_all_entities, [])}
    else
      {:noreply, state}
    end
  end

  def handle_info({:mqtt_message, topic_levels, payload}, %{config: config} = state) do
    if Runtime.export_enabled?(config) do
      Router.dispatch(topic_levels, payload, config, &publish/3)
    end

    {:noreply, state}
  end

  def handle_info({:control_state, kind, id, _control_state}, state)
      when kind in [:light, :group] do
    if Runtime.export_enabled?(state.config) and Runtime.lights_enabled?(state.config) and
         Connection.alive?(state.connection_pid) do
      {:noreply, run_sync(state, :publish_entity, [kind, id])}
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp configure(state) do
    config = export_config()
    state = maybe_unpublish_removed_entities(state, config)

    cond do
      not Runtime.export_enabled?(config) ->
        state
        |> publish_availability_if_connected("offline")
        |> stop_connection()
        |> Map.put(:config, config)

      Runtime.same_config?(state.config, config) and Connection.alive?(state.connection_pid) ->
        %{state | config: config}

      true ->
        state
        |> publish_availability_if_connected("offline")
        |> stop_connection()
        |> start_connection(config)
    end
  end

  defp maybe_unpublish_removed_entities(%{config: previous} = state, config) do
    cond do
      not Connection.alive?(state.connection_pid) ->
        state

      not is_map(previous) ->
        state

      true ->
        if Runtime.scenes_enabled?(previous) and not Runtime.scenes_enabled?(config) do
          Sync.unpublish_all_scenes(&publish/3, previous)
        end

        if Runtime.room_selects_enabled?(previous) and
             not Runtime.room_selects_enabled?(config) do
          Sync.unpublish_all_room_selects(&publish/3, previous)
        end

        if Runtime.lights_enabled?(previous) and not Runtime.lights_enabled?(config) do
          Sync.unpublish_all_light_entities(&publish/3, previous)
        end

        state
    end
  end

  defp start_connection(state, config) do
    case Connection.start(client_id(), self(), config, Runtime.command_topic_filters()) do
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

  defp handle_export_cast(:refresh_all_scenes, state),
    do: run_sync(state, :publish_all_entities, [])

  defp handle_export_cast({:refresh_room, room_id}, state),
    do: run_sync(state, :publish_room_entities, [room_id])

  defp handle_export_cast({:refresh_room_select, room_id}, state),
    do: run_sync(state, :publish_room_select, [room_id])

  defp handle_export_cast({:refresh_light, light_id}, state),
    do: run_sync(state, :publish_entity, [:light, light_id])

  defp handle_export_cast({:refresh_group, group_id}, state),
    do: run_sync(state, :publish_entity, [:group, group_id])

  defp handle_export_cast({:refresh_scene, scene_id}, state),
    do: run_sync(state, :publish_scene, [scene_id])

  defp handle_export_cast({:remove_light, light_id}, state),
    do: run_sync(state, :unpublish_entity, [:light, light_id])

  defp handle_export_cast({:remove_group, group_id}, state),
    do: run_sync(state, :unpublish_entity, [:group, group_id])

  defp handle_export_cast({:remove_scene, scene_id}, state),
    do: run_sync(state, :unpublish_scene, [scene_id])

  defp handle_export_cast({:remove_room, room_id}, state),
    do: run_sync(state, :unpublish_room_select, [room_id])

  defp handle_export_cast(_message, state), do: state

  defp run_sync(state, function_name, extra_args) when is_list(extra_args) do
    :ok = apply(Sync, function_name, [(&publish/3) | extra_args] ++ [state.config])
    state
  end

  defp publish_availability_if_connected(state, value) do
    if Connection.alive?(state.connection_pid) do
      :ok = publish_availability(value)
    end

    state
  end

  defp publish_availability(value) do
    publish(availability_topic(), value, retain: true)
  end

  defp publish(topic, payload, opts) do
    Connection.publish(client_id(), topic, payload, opts)
  end

  defp maybe_cast(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, message)

      _ ->
        :ok
    end
  end
end
