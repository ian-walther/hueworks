defmodule Hueworks.HomeAssistant.Export do
  @moduledoc false

  use GenServer

  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.ServerState
  alias Hueworks.HomeAssistant.Export.Lifecycle
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Router
  alias Hueworks.HomeAssistant.Export.Runtime
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
    {:ok, ServerState.new(), {:continue, :configure}}
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
    {:noreply, Lifecycle.handle_cast(message, state, &publish/3)}
  end

  @impl true
  def handle_info({:mqtt_connected, connection_client_id}, state) do
    {:noreply, Lifecycle.handle_connected(connection_client_id, state, client_id(), &publish/3)}
  end

  def handle_info({:mqtt_message, topic_levels, payload}, %ServerState{config: config} = state) do
    if Runtime.export_enabled?(config) do
      Router.dispatch(topic_levels, payload, config, &publish/3)
    end

    {:noreply, state}
  end

  def handle_info({:control_state, kind, id, _control_state}, state)
      when kind in [:light, :group] do
    {:noreply, Lifecycle.handle_control_state(kind, id, state, &publish/3)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp configure(state) do
    state
    |> Lifecycle.configure(export_config(), client_id(), &publish/3)
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
