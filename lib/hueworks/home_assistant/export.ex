defmodule Hueworks.HomeAssistant.Export do
  @moduledoc false

  use GenServer

  alias Hueworks.ActiveScenes
  alias Hueworks.DomainEvents
  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.ServerState
  alias Hueworks.HomeAssistant.Export.Lifecycle
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Router
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.Instance
  alias Hueworks.Schemas.{Area, Group, Light, PresenceInput, Scene}
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

  def refresh_area(area_id) when is_integer(area_id) do
    maybe_cast({:refresh_area, area_id})
  end

  def refresh_area_select(area_id) when is_integer(area_id) do
    maybe_cast({:refresh_area_select, area_id})
  end

  def refresh_light(%Light{id: light_id}), do: refresh_light(light_id)

  def refresh_light(light_id) when is_integer(light_id) do
    maybe_cast({:refresh_light, light_id})
  end

  def refresh_group(%Group{id: group_id}), do: refresh_group(group_id)

  def refresh_group(group_id) when is_integer(group_id) do
    maybe_cast({:refresh_group, group_id})
  end

  def refresh_presence_input(%PresenceInput{id: input_id}), do: refresh_presence_input(input_id)

  def refresh_presence_input(input_id) when is_integer(input_id) do
    maybe_cast({:refresh_presence_input, input_id})
  end

  def refresh_presence_inputs_for_area(area_id) when is_integer(area_id) do
    maybe_cast({:refresh_presence_inputs_for_area, area_id})
  end

  def remove_light(%Light{id: light_id}), do: remove_light(light_id)

  def remove_light(light_id) when is_integer(light_id) do
    maybe_cast({:remove_light, light_id})
  end

  def remove_group(%Group{id: group_id}), do: remove_group(group_id)

  def remove_group(group_id) when is_integer(group_id) do
    maybe_cast({:remove_group, group_id})
  end

  def remove_presence_input(%PresenceInput{id: input_id}), do: remove_presence_input(input_id)

  def remove_presence_input(input_id) when is_integer(input_id) do
    maybe_cast({:remove_presence_input, input_id})
  end

  def refresh_scene(%Scene{id: scene_id}), do: refresh_scene(scene_id)

  def refresh_scene(scene_id) when is_integer(scene_id) do
    maybe_cast({:refresh_scene, scene_id})
  end

  def remove_scene(%Scene{id: scene_id}), do: remove_scene(scene_id)

  def remove_scene(scene_id) when is_integer(scene_id) do
    maybe_cast({:remove_scene, scene_id})
  end

  def remove_area(%Area{id: area_id, ha_scene_select_identifier: identifier})
      when is_integer(area_id) and is_binary(identifier) do
    maybe_cast({:remove_area, area_id, identifier})
  end

  def client_id do
    "hwhaexp-#{Instance.slug()}"
  end

  defdelegate availability_topic(), to: Messages
  defdelegate command_topic(scene_id), to: Messages
  defdelegate attributes_topic(scene_id), to: Messages
  defdelegate area_select_command_topic(area_id), to: Messages
  defdelegate area_select_state_topic(area_id), to: Messages
  defdelegate area_select_attributes_topic(area_id), to: Messages
  defdelegate entity_attributes_topic(kind, id), to: Messages
  defdelegate presence_input_attributes_topic(id), to: Messages
  defdelegate switch_command_topic(kind, id), to: Messages
  defdelegate presence_input_command_topic(id), to: Messages
  defdelegate switch_state_topic(kind, id), to: Messages
  defdelegate presence_input_state_topic(id), to: Messages
  defdelegate light_command_topic(kind, id), to: Messages
  defdelegate light_state_topic(kind, id), to: Messages

  def discovery_topic(scene_id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.discovery_topic(scene_id, discovery_prefix)

  def area_select_discovery_topic(identifier, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.area_select_discovery_topic(identifier, discovery_prefix)

  def switch_discovery_topic(kind, id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.switch_discovery_topic(kind, id, discovery_prefix)

  def presence_input_discovery_topic(id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.presence_input_discovery_topic(id, discovery_prefix)

  def light_discovery_topic(kind, id, discovery_prefix \\ @default_discovery_prefix),
    do: Messages.light_discovery_topic(kind, id, discovery_prefix)

  def command_scene_id(topic_levels, topic_prefix \\ @default_topic_prefix),
    do: Messages.command_scene_id(topic_levels, topic_prefix)

  def command_area_id(topic_levels, topic_prefix \\ @default_topic_prefix),
    do: Messages.command_area_id(topic_levels, topic_prefix)

  def discovery_payload(scene, config \\ export_config()),
    do: Messages.discovery_payload(scene, config)

  defdelegate scene_attributes_payload(scene), to: Messages

  def area_select_discovery_payload(area, scenes, config \\ export_config()),
    do: Messages.area_select_discovery_payload(area, scenes, config)

  defdelegate area_select_attributes_payload(area, scenes), to: Messages

  def switch_discovery_payload(kind, entity, config \\ export_config()),
    do: Messages.switch_discovery_payload(kind, entity, config)

  def light_discovery_payload(kind, entity, config \\ export_config()),
    do: Messages.light_discovery_payload(kind, entity, config)

  defdelegate entity_attributes_payload(kind, entity), to: Messages

  def presence_input_discovery_payload(input, config \\ export_config()),
    do: Messages.presence_input_discovery_payload(input, config)

  defdelegate presence_input_attributes_payload(input), to: Messages

  def export_config do
    Runtime.export_config()
  end

  @impl true
  def init(_state) do
    PubSub.subscribe(Hueworks.PubSub, "control_state")
    PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())
    PubSub.subscribe(Hueworks.PubSub, DomainEvents.topic())
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

  def handle_info({:active_scene_updated, area_id, _scene_id}, state) when is_integer(area_id) do
    {:noreply, handle_sync(state, {:refresh_area_select, area_id})}
  end

  def handle_info({:scene_saved, %Scene{id: scene_id, area_id: area_id}}, state) do
    state =
      state
      |> handle_sync({:refresh_scene, scene_id})
      |> handle_sync({:refresh_area, area_id})

    {:noreply, state}
  end

  def handle_info({:scene_deleted, %Scene{id: scene_id, area_id: area_id}}, state) do
    state =
      state
      |> handle_sync({:remove_scene, scene_id})
      |> handle_sync({:refresh_area, area_id})

    {:noreply, state}
  end

  def handle_info({:presence_input_changed, %PresenceInput{id: input_id}}, state) do
    {:noreply, handle_sync(state, {:refresh_presence_input, input_id})}
  end

  def handle_info({:presence_input_deleted, input_id}, state) when is_integer(input_id) do
    {:noreply, handle_sync(state, {:remove_presence_input, input_id})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp configure(state) do
    state
    |> Lifecycle.configure(export_config(), client_id(), &publish/3)
  end

  defp handle_sync(state, message) do
    Lifecycle.handle_cast(message, state, &publish/3)
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
