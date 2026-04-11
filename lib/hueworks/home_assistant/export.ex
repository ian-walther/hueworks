defmodule Hueworks.HomeAssistant.Export do
  @moduledoc false

  use GenServer

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Control.State
  alias Hueworks.Groups
  alias Hueworks.Instance
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Group, Light, Room, Scene}
  alias Hueworks.Util
  alias Phoenix.PubSub

  @default_port 1883
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

  def availability_topic, do: "#{@default_topic_prefix}/status"

  def command_topic(scene_id) when is_integer(scene_id),
    do: "#{@default_topic_prefix}/scenes/#{scene_id}/set"

  def attributes_topic(scene_id) when is_integer(scene_id),
    do: "#{@default_topic_prefix}/scenes/#{scene_id}/attributes"

  def room_select_command_topic(room_id) when is_integer(room_id),
    do: "#{@default_topic_prefix}/rooms/#{room_id}/scene/set"

  def room_select_state_topic(room_id) when is_integer(room_id),
    do: "#{@default_topic_prefix}/rooms/#{room_id}/scene/state"

  def room_select_attributes_topic(room_id) when is_integer(room_id),
    do: "#{@default_topic_prefix}/rooms/#{room_id}/scene/attributes"

  def entity_attributes_topic(kind, id)
      when kind in [:light, :group] and is_integer(id),
      do: "#{@default_topic_prefix}/#{kind_segment(kind)}/#{id}/attributes"

  def switch_command_topic(kind, id)
      when kind in [:light, :group] and is_integer(id),
      do: "#{@default_topic_prefix}/#{kind_segment(kind)}/#{id}/switch/set"

  def switch_state_topic(kind, id)
      when kind in [:light, :group] and is_integer(id),
      do: "#{@default_topic_prefix}/#{kind_segment(kind)}/#{id}/switch/state"

  def light_command_topic(kind, id)
      when kind in [:light, :group] and is_integer(id),
      do: "#{@default_topic_prefix}/#{kind_segment(kind)}/#{id}/light/set"

  def light_state_topic(kind, id)
      when kind in [:light, :group] and is_integer(id),
      do: "#{@default_topic_prefix}/#{kind_segment(kind)}/#{id}/light/state"

  def discovery_topic(scene_id, discovery_prefix \\ @default_discovery_prefix)
      when is_integer(scene_id) and is_binary(discovery_prefix) do
    "#{discovery_prefix}/scene/hueworks_scene_#{scene_id}/config"
  end

  def room_select_discovery_topic(room_id, discovery_prefix \\ @default_discovery_prefix)
      when is_integer(room_id) and is_binary(discovery_prefix) do
    "#{discovery_prefix}/select/hueworks_room_scene_select_#{room_id}/config"
  end

  def switch_discovery_topic(kind, id, discovery_prefix \\ @default_discovery_prefix)
      when kind in [:light, :group] and is_integer(id) and is_binary(discovery_prefix) do
    "#{discovery_prefix}/switch/#{entity_object_id(kind, id)}/config"
  end

  def light_discovery_topic(kind, id, discovery_prefix \\ @default_discovery_prefix)
      when kind in [:light, :group] and is_integer(id) and is_binary(discovery_prefix) do
    "#{discovery_prefix}/light/#{entity_object_id(kind, id)}/config"
  end

  def command_scene_id(topic_levels, topic_prefix \\ @default_topic_prefix)

  def command_scene_id(topic, topic_prefix) when is_binary(topic) and is_binary(topic_prefix) do
    topic
    |> String.split("/", trim: true)
    |> command_scene_id(topic_prefix)
  end

  def command_scene_id(topic_levels, topic_prefix)
      when is_list(topic_levels) and is_binary(topic_prefix) do
    prefix_levels = String.split("#{topic_prefix}/scenes", "/", trim: true)

    if Enum.take(topic_levels, length(prefix_levels)) == prefix_levels do
      case Enum.drop(topic_levels, length(prefix_levels)) do
        [scene_id, "set"] ->
          case Integer.parse(scene_id) do
            {parsed, ""} -> parsed
            _ -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  def command_scene_id(_topic_levels, _topic_prefix), do: nil

  def command_room_id(topic_levels, topic_prefix \\ @default_topic_prefix)

  def command_room_id(topic, topic_prefix) when is_binary(topic) and is_binary(topic_prefix) do
    topic
    |> String.split("/", trim: true)
    |> command_room_id(topic_prefix)
  end

  def command_room_id(topic_levels, topic_prefix)
      when is_list(topic_levels) and is_binary(topic_prefix) do
    prefix_levels = String.split("#{topic_prefix}/rooms", "/", trim: true)

    if Enum.take(topic_levels, length(prefix_levels)) == prefix_levels do
      case Enum.drop(topic_levels, length(prefix_levels)) do
        [room_id, "scene", "set"] ->
          case Integer.parse(room_id) do
            {parsed, ""} -> parsed
            _ -> nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  def command_room_id(_topic_levels, _topic_prefix), do: nil

  def discovery_payload(%Scene{} = scene, config \\ export_config()) do
    room_name = room_name(scene.room)

    %{
      "platform" => "scene",
      "name" => scene_name(scene),
      "unique_id" => "hueworks_scene_#{scene.id}",
      "command_topic" => command_topic(scene.id),
      "payload_on" => "ON",
      "availability_topic" => availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => attributes_topic(scene.id),
      "device" => %{
        "identifiers" => ["hueworks_room_#{scene.room_id}"],
        "name" => "HueWorks #{room_name}",
        "manufacturer" => "HueWorks",
        "model" => "Room Scenes"
      }
    }
    |> maybe_put("configuration_url", config[:configuration_url])
  end

  def scene_attributes_payload(%Scene{} = scene) do
    %{
      "hueworks_managed" => true,
      "hueworks_scene_id" => scene.id,
      "hueworks_room_id" => scene.room_id,
      "room_name" => room_name(scene.room),
      "scene_name" => scene_name(scene)
    }
  end

  def room_select_discovery_payload(%Room{} = room, scenes, config \\ export_config())
      when is_list(scenes) do
    %{
      "platform" => "select",
      "name" => "Scene",
      "unique_id" => "hueworks_room_scene_select_#{room.id}",
      "command_topic" => room_select_command_topic(room.id),
      "state_topic" => room_select_state_topic(room.id),
      "availability_topic" => availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => room_select_attributes_topic(room.id),
      "options" => room_select_option_labels(scenes),
      "device" => %{
        "identifiers" => ["hueworks_room_#{room.id}"],
        "name" => "HueWorks #{room_name(room)}",
        "manufacturer" => "HueWorks",
        "model" => "Room Scenes"
      }
    }
    |> maybe_put("configuration_url", config[:configuration_url])
  end

  def room_select_attributes_payload(%Room{} = room, scenes) when is_list(scenes) do
    active_scene = ActiveScenes.get_for_room(room.id)

    %{
      "hueworks_managed" => true,
      "hueworks_room_id" => room.id,
      "room_name" => room_name(room),
      "active_scene_id" => active_scene && active_scene.scene_id,
      "active_scene_name" => active_scene_name(room.id, scenes),
      "scene_options" => room_select_option_labels(scenes)
    }
  end

  def switch_discovery_payload(kind, entity, config \\ export_config())
      when kind in [:light, :group] and is_map(entity) do
    %{
      "platform" => "switch",
      "name" => entity_name(entity),
      "unique_id" => entity_unique_id(kind, :switch, entity.id),
      "command_topic" => switch_command_topic(kind, entity.id),
      "state_topic" => switch_state_topic(kind, entity.id),
      "payload_on" => "ON",
      "payload_off" => "OFF",
      "availability_topic" => availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => entity_attributes_topic(kind, entity.id),
      "device" => room_device(entity)
    }
    |> maybe_put("configuration_url", config[:configuration_url])
  end

  def light_discovery_payload(kind, entity, config \\ export_config())
      when kind in [:light, :group] and is_map(entity) do
    %{
      "platform" => "light",
      "schema" => "json",
      "name" => entity_name(entity),
      "unique_id" => entity_unique_id(kind, :light, entity.id),
      "command_topic" => light_command_topic(kind, entity.id),
      "state_topic" => light_state_topic(kind, entity.id),
      "availability_topic" => availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => entity_attributes_topic(kind, entity.id),
      "brightness_scale" => 100,
      "supported_color_modes" => supported_color_modes(entity),
      "transition" => false,
      "device" => room_device(entity)
    }
    |> maybe_put("configuration_url", config[:configuration_url])
    |> maybe_put_kelvin_range(entity)
  end

  def entity_attributes_payload(kind, entity)
      when kind in [:light, :group] and is_map(entity) do
    %{
      "hueworks_managed" => true,
      "hueworks_entity_kind" => Atom.to_string(kind),
      "hueworks_entity_id" => entity.id,
      "hueworks_export_mode" => Atom.to_string(entity.ha_export_mode || :none),
      "hueworks_room_id" => entity.room_id,
      "room_name" => room_name(entity.room),
      "entity_name" => entity_name(entity),
      "source" => to_string(entity.source)
    }
  end

  def export_config do
    settings = AppSettings.get_global()

    %{
      enabled:
        settings.ha_export_scenes_enabled == true or
          settings.ha_export_room_selects_enabled == true or
          settings.ha_export_lights_enabled == true,
      scenes_enabled: settings.ha_export_scenes_enabled == true,
      room_selects_enabled: settings.ha_export_room_selects_enabled == true,
      lights_enabled: settings.ha_export_lights_enabled == true,
      host: settings.ha_export_mqtt_host,
      port: settings.ha_export_mqtt_port || @default_port,
      username: settings.ha_export_mqtt_username,
      password: settings.ha_export_mqtt_password,
      discovery_prefix: settings.ha_export_discovery_prefix || @default_discovery_prefix
    }
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

  def handle_cast(:refresh_all_scenes, state) do
    {:noreply, publish_all_entities(state)}
  end

  def handle_cast({:refresh_room, room_id}, state) do
    {:noreply, publish_room_entities(room_id, state)}
  end

  def handle_cast({:refresh_room_select, room_id}, state) do
    {:noreply, publish_room_select(room_id, state)}
  end

  def handle_cast({:refresh_light, light_id}, state) do
    {:noreply, publish_entity(:light, light_id, state)}
  end

  def handle_cast({:refresh_group, group_id}, state) do
    {:noreply, publish_entity(:group, group_id, state)}
  end

  def handle_cast({:refresh_scene, scene_id}, state) do
    {:noreply, publish_scene(scene_id, state)}
  end

  def handle_cast({:remove_light, light_id}, state) do
    {:noreply, unpublish_entity(:light, light_id, state)}
  end

  def handle_cast({:remove_group, group_id}, state) do
    {:noreply, unpublish_entity(:group, group_id, state)}
  end

  def handle_cast({:remove_scene, scene_id}, state) do
    {:noreply, unpublish_scene(scene_id, state)}
  end

  def handle_cast({:remove_room, room_id}, state) do
    {:noreply, unpublish_room_select(room_id, state)}
  end

  @impl true
  def handle_info({:mqtt_connected, connection_client_id}, %{config: config} = state) do
    if connection_client_id == client_id() and export_enabled?(config) do
      :ok = publish_availability("online")
      {:noreply, publish_all_entities(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:mqtt_message, topic_levels, payload}, %{config: config} = state) do
    if export_enabled?(config) do
      normalized_payload = normalize_payload(payload)

      case {command_scene_id(topic_levels), command_room_id(topic_levels),
            command_export_target(topic_levels), normalized_payload} do
        {scene_id, _room_id, _entity_command, "ON"} when is_integer(scene_id) ->
          case Scenes.activate_scene(scene_id, trace: %{source: :home_assistant_mqtt_export}) do
            {:ok, _diff, _updated} ->
              :ok

            {:error, reason} ->
              Logger.warning("HA export scene activation failed: #{inspect(reason)}")
          end

        {_scene_id, room_id, _entity_command, option_label} when is_integer(room_id) ->
          handle_room_select_command(room_id, option_label)

        {_scene_id, _room_id, %{kind: kind, id: id, mode: :switch}, command_payload} ->
          handle_switch_command(kind, id, command_payload)

        {_scene_id, _room_id, %{kind: kind, id: id, mode: :light}, command_payload} ->
          handle_light_command(kind, id, command_payload)

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  def handle_info({:control_state, kind, id, _control_state}, state)
      when kind in [:light, :group] do
    if export_enabled?(state.config) and lights_enabled?(state.config) and
         connection_alive?(state.connection_pid) do
      {:noreply, publish_entity(kind, id, state)}
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp configure(state) do
    config = export_config()
    state = maybe_unpublish_removed_entities(state, config)

    cond do
      not export_enabled?(config) ->
        state
        |> publish_availability_if_connected("offline")
        |> stop_connection()
        |> Map.put(:config, config)

      same_config?(state.config, config) and connection_alive?(state.connection_pid) ->
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
      not connection_alive?(state.connection_pid) ->
        state

      not is_map(previous) ->
        state

      true ->
        if scenes_enabled?(previous) and not scenes_enabled?(config) do
          unpublish_all_scenes(previous)
        end

        if room_selects_enabled?(previous) and not room_selects_enabled?(config) do
          unpublish_all_room_selects(previous)
        end

        if lights_enabled?(previous) and not lights_enabled?(config) do
          unpublish_all_light_entities(previous)
        end

        state
    end
  end

  defp start_connection(state, config) do
    start_opts =
      [
        client_id: client_id(),
        handler: {__MODULE__.Handler, [self(), client_id(), command_topic_filters()]},
        server: {Tortoise.Transport.Tcp, host: String.to_charlist(config.host), port: config.port}
      ]
      |> maybe_put_auth(config)

    case supervisor_module().start_child(start_opts) do
      {:ok, pid} ->
        %{state | config: config, connection_pid: pid}

      {:error, {:already_started, pid}} ->
        %{state | config: config, connection_pid: pid}

      {:error, reason} ->
        Logger.warning(
          "Failed to start Home Assistant export MQTT connection: #{inspect(reason)}"
        )

        %{state | config: config, connection_pid: nil}
    end
  end

  defp stop_connection(%{connection_pid: nil} = state), do: %{state | connection_pid: nil}

  defp stop_connection(%{connection_pid: pid} = state) do
    _ = dynamic_supervisor_module().terminate_child(tortoise_supervisor_name(), pid)
    %{state | connection_pid: nil}
  end

  defp publish_all_entities(state) do
    if export_enabled?(state.config) do
      if scenes_enabled?(state.config) do
        list_exportable_scenes()
        |> Enum.each(fn scene ->
          :ok = publish_scene_payloads(scene, state.config)
        end)
      end

      if room_selects_enabled?(state.config) do
        list_rooms()
        |> Enum.each(fn room ->
          :ok = publish_room_select_payloads(room, state.config)
        end)
      end

      if lights_enabled?(state.config) do
        list_exportable_lights()
        |> Enum.each(fn light ->
          :ok = sync_entity_payloads(:light, light, state.config)
        end)

        list_exportable_groups()
        |> Enum.each(fn group ->
          :ok = sync_entity_payloads(:group, group, state.config)
        end)
      end
    end

    state
  end

  defp publish_room_entities(room_id, state) do
    if export_enabled?(state.config) do
      if scenes_enabled?(state.config) do
        list_exportable_scenes_for_room(room_id)
        |> Enum.each(fn scene ->
          :ok = publish_scene_payloads(scene, state.config)
        end)
      end

      if room_selects_enabled?(state.config) do
        :ok = publish_room_select_payloads(room_id, state.config)
      end

      if lights_enabled?(state.config) do
        list_exportable_lights_for_room(room_id)
        |> Enum.each(fn light ->
          :ok = sync_entity_payloads(:light, light, state.config)
        end)

        list_exportable_groups_for_room(room_id)
        |> Enum.each(fn group ->
          :ok = sync_entity_payloads(:group, group, state.config)
        end)
      end
    end

    state
  end

  defp publish_scene(scene_id, state) do
    if export_enabled?(state.config) do
      case exportable_scene(scene_id) do
        %Scene{} = scene ->
          if scenes_enabled?(state.config) do
            :ok = publish_scene_payloads(scene, state.config)
          end

          if room_selects_enabled?(state.config) do
            :ok = publish_room_select_payloads(scene.room_id, state.config)
          end

        nil ->
          :ok
      end
    end

    state
  end

  defp unpublish_scene(scene_id, state) do
    if export_enabled?(state.config) do
      room_id =
        case exportable_scene(scene_id) do
          %Scene{} = scene -> scene.room_id
          nil -> nil
        end

      if scenes_enabled?(state.config) do
        :ok = unpublish_scene_payloads(scene_id, state.config)
      end

      if is_integer(room_id) and room_selects_enabled?(state.config) do
        :ok = publish_room_select_payloads(room_id, state.config)
      end
    end

    state
  end

  defp publish_room_select(room_id, state) do
    if export_enabled?(state.config) and room_selects_enabled?(state.config) do
      :ok = publish_room_select_payloads(room_id, state.config)
    end

    state
  end

  defp publish_entity(kind, id, state) when kind in [:light, :group] and is_integer(id) do
    if export_enabled?(state.config) and lights_enabled?(state.config) do
      :ok = sync_entity_payloads(kind, fetch_entity(kind, id), state.config)
    end

    state
  end

  defp unpublish_entity(kind, id, state) when kind in [:light, :group] and is_integer(id) do
    if export_enabled?(state.config) and lights_enabled?(state.config) do
      :ok = unpublish_entity_payloads(kind, id, state.config)
    end

    state
  end

  defp unpublish_room_select(room_id, state) do
    if export_enabled?(state.config) and room_selects_enabled?(state.config) do
      :ok = unpublish_room_select_payloads(room_id, state.config)
    end

    state
  end

  defp publish_scene_payloads(%Scene{} = scene, config) do
    discovery = discovery_topic(scene.id, config.discovery_prefix)
    attributes = attributes_topic(scene.id)

    :ok = publish(discovery, Jason.encode!(discovery_payload(scene, config)), retain: true)
    :ok = publish(attributes, Jason.encode!(scene_attributes_payload(scene)), retain: true)
  end

  defp unpublish_scene_payloads(scene_id, config) do
    discovery = discovery_topic(scene_id, config.discovery_prefix)
    attributes = attributes_topic(scene_id)

    :ok = publish(discovery, "", retain: true)
    :ok = publish(attributes, "", retain: true)
  end

  defp sync_entity_payloads(_kind, nil, config) do
    _ = config
    :ok
  end

  defp sync_entity_payloads(kind, entity, config)
       when kind in [:light, :group] and is_map(entity) do
    case entity_export_mode(entity) do
      :switch ->
        :ok = publish_switch_payloads(kind, entity, config)
        :ok = unpublish_light_payloads(kind, entity.id, config)

      :light ->
        :ok = publish_light_payloads(kind, entity, config)
        :ok = unpublish_switch_payloads(kind, entity.id, config)

      _ ->
        :ok = unpublish_entity_payloads(kind, entity.id, config)
    end
  end

  defp publish_switch_payloads(kind, entity, config)
       when kind in [:light, :group] and is_map(entity) do
    discovery = switch_discovery_topic(kind, entity.id, config.discovery_prefix)
    attributes = entity_attributes_topic(kind, entity.id)
    state_topic = switch_state_topic(kind, entity.id)

    :ok =
      publish(discovery, Jason.encode!(switch_discovery_payload(kind, entity, config)),
        retain: true
      )

    :ok =
      publish(attributes, Jason.encode!(entity_attributes_payload(kind, entity)), retain: true)

    :ok = publish(state_topic, switch_state_payload(kind, entity.id), retain: true)
  end

  defp publish_light_payloads(kind, entity, config)
       when kind in [:light, :group] and is_map(entity) do
    discovery = light_discovery_topic(kind, entity.id, config.discovery_prefix)
    attributes = entity_attributes_topic(kind, entity.id)
    state_topic = light_state_topic(kind, entity.id)

    :ok =
      publish(discovery, Jason.encode!(light_discovery_payload(kind, entity, config)),
        retain: true
      )

    :ok =
      publish(attributes, Jason.encode!(entity_attributes_payload(kind, entity)), retain: true)

    :ok = publish(state_topic, Jason.encode!(light_state_payload(kind, entity)), retain: true)
  end

  defp unpublish_entity_payloads(kind, id, config)
       when kind in [:light, :group] and is_integer(id) do
    :ok = unpublish_switch_payloads(kind, id, config)
    :ok = unpublish_light_payloads(kind, id, config)
    :ok = publish(entity_attributes_topic(kind, id), "", retain: true)
  end

  defp unpublish_switch_payloads(kind, id, config)
       when kind in [:light, :group] and is_integer(id) do
    :ok = publish(switch_discovery_topic(kind, id, config.discovery_prefix), "", retain: true)
    :ok = publish(switch_state_topic(kind, id), "None", retain: true)
  end

  defp unpublish_light_payloads(kind, id, config)
       when kind in [:light, :group] and is_integer(id) do
    :ok = publish(light_discovery_topic(kind, id, config.discovery_prefix), "", retain: true)
    :ok = publish(light_state_topic(kind, id), Jason.encode!(%{"state" => nil}), retain: true)
  end

  defp publish_room_select_payloads(%Room{} = room, config) do
    scenes = list_exportable_scenes_for_room(room.id)

    if scenes == [] do
      unpublish_room_select_payloads(room.id, config)
    else
      discovery = room_select_discovery_topic(room.id, config.discovery_prefix)
      state_topic = room_select_state_topic(room.id)
      attributes_topic = room_select_attributes_topic(room.id)

      :ok =
        publish(discovery, Jason.encode!(room_select_discovery_payload(room, scenes, config)),
          retain: true
        )

      :ok =
        publish(attributes_topic, Jason.encode!(room_select_attributes_payload(room, scenes)),
          retain: true
        )

      :ok = publish(state_topic, room_select_state_payload(room.id, scenes), retain: true)
    end
  end

  defp publish_room_select_payloads(room_id, config) when is_integer(room_id) do
    case Repo.get(Room, room_id) do
      %Room{} = room -> publish_room_select_payloads(room, config)
      nil -> unpublish_room_select_payloads(room_id, config)
    end
  end

  defp unpublish_room_select_payloads(room_id, config) do
    discovery = room_select_discovery_topic(room_id, config.discovery_prefix)
    attributes = room_select_attributes_topic(room_id)
    state = room_select_state_topic(room_id)

    :ok = publish(discovery, "", retain: true)
    :ok = publish(attributes, "", retain: true)
    :ok = publish(state, "None", retain: true)
  end

  defp unpublish_all_scenes(config) do
    list_exportable_scenes()
    |> Enum.each(fn scene ->
      :ok = unpublish_scene_payloads(scene.id, config)
    end)
  end

  defp unpublish_all_room_selects(config) do
    list_rooms()
    |> Enum.each(fn room ->
      :ok = unpublish_room_select_payloads(room.id, config)
    end)
  end

  defp unpublish_all_light_entities(config) do
    list_controllable_light_ids()
    |> Enum.each(fn light_id ->
      :ok = unpublish_entity_payloads(:light, light_id, config)
    end)

    list_controllable_group_ids()
    |> Enum.each(fn group_id ->
      :ok = unpublish_entity_payloads(:group, group_id, config)
    end)
  end

  defp publish_availability_if_connected(state, value) do
    if connection_alive?(state.connection_pid) do
      :ok = publish_availability(value)
    end

    state
  end

  defp publish_availability(value) do
    publish(availability_topic(), value, retain: true)
  end

  defp publish(topic, payload, opts) do
    publish_opts = [qos: 0, retain: Keyword.get(opts, :retain, false)]

    case tortoise_module().publish(client_id(), topic, payload, publish_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish Home Assistant export MQTT payload: #{inspect(reason)}")
        :ok
    end
  end

  defp list_exportable_scenes do
    Repo.all(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        preload: [room: r],
        order_by: [asc: r.name, asc: s.name]
      )
    )
  end

  defp list_rooms do
    Repo.all(from(r in Room, order_by: [asc: r.name]))
  end

  defp list_exportable_scenes_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        where: s.room_id == ^room_id,
        preload: [room: r],
        order_by: [asc: s.name]
      )
    )
  end

  defp exportable_scene(scene_id) when is_integer(scene_id) do
    Repo.one(
      from(s in Scene,
        join: r in Room,
        on: r.id == s.room_id,
        where: s.id == ^scene_id,
        preload: [room: r]
      )
    )
  end

  defp scene_for_room_option(room_id, option_label)
       when is_integer(room_id) and is_binary(option_label) do
    room_id
    |> list_exportable_scenes_for_room()
    |> room_scene_options()
    |> Enum.find_value(fn %{label: label, scene: scene} ->
      if label == option_label, do: scene, else: nil
    end)
  end

  defp scene_for_room_option(_room_id, _option_label), do: nil

  defp handle_room_select_command(room_id, option_label)
       when is_integer(room_id) and option_label in ["None", ""] do
    ActiveScenes.clear_for_room(room_id)
  end

  defp handle_room_select_command(room_id, option_label)
       when is_integer(room_id) and is_binary(option_label) do
    case scene_for_room_option(room_id, option_label) do
      %Scene{} = scene ->
        case Scenes.activate_scene(scene.id,
               trace: %{source: :home_assistant_mqtt_export_select}
             ) do
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

  defp handle_switch_command(kind, id, payload)
       when kind in [:light, :group] and is_integer(id) and is_binary(payload) do
    case normalize_power_payload(payload) do
      :on ->
        apply_power_command(kind, id, :on)

      :off ->
        apply_power_command(kind, id, :off)

      _ ->
        :ok
    end
  end

  defp handle_switch_command(_kind, _id, _payload), do: :ok

  defp handle_light_command(kind, id, payload) when kind in [:light, :group] and is_integer(id) do
    with entity when not is_nil(entity) <- fetch_entity(kind, id),
         {:ok, decoded} <- decode_json_payload(payload),
         {room_id, light_ids} when is_integer(room_id) and light_ids != [] <-
           control_target(kind, id),
         {:ok, action} <- normalize_light_command(decoded, entity) do
      case action do
        {:power, power} ->
          case ManualControl.apply_power_action(room_id, light_ids, power) do
            {:ok, _diff} ->
              :ok

            {:error, reason} ->
              Logger.warning("HA export power command failed: #{inspect(reason)}")
          end

        {:set_state, attrs} ->
          case ManualControl.apply_updates(room_id, light_ids, attrs) do
            {:ok, _diff} ->
              :ok

            {:error, reason} ->
              Logger.warning("HA export light command failed: #{inspect(reason)}")
          end
      end
    else
      _ -> :ok
    end
  end

  defp normalize_light_command(%{} = payload, entity) when is_map(entity) do
    state = normalize_power_payload(Map.get(payload, "state"))
    brightness = normalize_export_brightness(Map.get(payload, "brightness"))

    kelvin =
      if entity.supports_temp == true do
        normalize_export_kelvin(Map.get(payload, "color_temp"))
      end

    {x, y} =
      if entity.supports_color == true do
        normalize_export_xy(Map.get(payload, "color"))
      else
        {nil, nil}
      end

    attrs =
      %{}
      |> maybe_put(:brightness, brightness)
      |> maybe_put(:kelvin, kelvin)
      |> maybe_put(:x, x)
      |> maybe_put(:y, y)
      |> maybe_put(
        :power,
        if(
          map_size(
            %{}
            |> maybe_put(:brightness, brightness)
            |> maybe_put(:kelvin, kelvin)
            |> maybe_put(:x, x)
            |> maybe_put(:y, y)
          ) > 0,
          do: :on
        )
      )

    cond do
      state == :off ->
        {:ok, {:power, :off}}

      state == :on and map_size(attrs) == 0 ->
        {:ok, {:power, :on}}

      map_size(attrs) > 0 ->
        {:ok, {:set_state, attrs}}

      true ->
        :error
    end
  end

  defp normalize_light_command(_payload, _entity), do: :error

  defp decode_json_payload(payload) when is_binary(payload) do
    case Jason.decode(String.trim(payload)) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> :error
    end
  end

  defp decode_json_payload(payload) do
    payload
    |> IO.iodata_to_binary()
    |> decode_json_payload()
  end

  defp apply_power_command(kind, id, power)
       when kind in [:light, :group] and power in [:on, :off] do
    case control_target(kind, id) do
      {room_id, light_ids} when is_integer(room_id) and light_ids != [] ->
        case ManualControl.apply_power_action(room_id, light_ids, power) do
          {:ok, _diff} ->
            :ok

          {:error, reason} ->
            Logger.warning("HA export switch command failed: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  end

  defp control_target(:light, light_id) when is_integer(light_id) do
    case fetch_entity(:light, light_id) do
      %Light{} = light -> {light.room_id, [light.id]}
      _ -> nil
    end
  end

  defp control_target(:group, group_id) when is_integer(group_id) do
    case fetch_entity(:group, group_id) do
      %Group{} = group ->
        light_ids = Groups.member_light_ids(group.id)
        {group.room_id, light_ids}

      _ ->
        nil
    end
  end

  defp fetch_entity(:light, light_id) when is_integer(light_id) do
    Repo.one(
      from(l in Light,
        where: l.id == ^light_id and is_nil(l.canonical_light_id)
      )
    )
    |> Repo.preload(:room)
  end

  defp fetch_entity(:group, group_id) when is_integer(group_id) do
    Repo.one(
      from(g in Group,
        where: g.id == ^group_id and is_nil(g.canonical_group_id)
      )
    )
    |> Repo.preload([:room, :lights])
  end

  defp list_exportable_lights do
    Repo.all(
      from(l in Light,
        where: is_nil(l.canonical_light_id) and l.enabled == true and l.ha_export_mode != :none,
        order_by: [asc: l.name]
      )
    )
    |> Repo.preload(:room)
  end

  defp list_exportable_groups do
    Repo.all(
      from(g in Group,
        where: is_nil(g.canonical_group_id) and g.enabled == true and g.ha_export_mode != :none,
        order_by: [asc: g.name]
      )
    )
    |> Repo.preload([:room, :lights])
  end

  defp list_exportable_lights_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(l in Light,
        where:
          l.room_id == ^room_id and is_nil(l.canonical_light_id) and l.enabled == true and
            l.ha_export_mode != :none,
        order_by: [asc: l.name]
      )
    )
    |> Repo.preload(:room)
  end

  defp list_exportable_groups_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(g in Group,
        where:
          g.room_id == ^room_id and is_nil(g.canonical_group_id) and g.enabled == true and
            g.ha_export_mode != :none,
        order_by: [asc: g.name]
      )
    )
    |> Repo.preload([:room, :lights])
  end

  defp list_controllable_light_ids do
    Repo.all(
      from(l in Light,
        where: is_nil(l.canonical_light_id),
        select: l.id
      )
    )
  end

  defp list_controllable_group_ids do
    Repo.all(
      from(g in Group,
        where: is_nil(g.canonical_group_id),
        select: g.id
      )
    )
  end

  defp light_state_payload(kind, entity) when kind in [:light, :group] and is_map(entity) do
    state = State.get(kind, entity.id) || %{}
    power = state_power_value(state)

    brightness =
      normalize_export_brightness(Map.get(state, :brightness) || Map.get(state, "brightness"))

    kelvin =
      normalize_export_kelvin(
        Map.get(state, :kelvin) || Map.get(state, "kelvin") || Map.get(state, :temperature) ||
          Map.get(state, "temperature")
      )

    x = normalize_xy_value(Map.get(state, :x) || Map.get(state, "x"))
    y = normalize_xy_value(Map.get(state, :y) || Map.get(state, "y"))

    %{"state" => power_to_mqtt_json(power)}
    |> maybe_put("brightness", brightness)
    |> maybe_put_color_state(entity, kelvin, x, y)
  end

  defp switch_state_payload(kind, id) when kind in [:light, :group] and is_integer(id) do
    case State.get(kind, id) |> state_power_value() do
      :on -> "ON"
      :off -> "OFF"
      _ -> "None"
    end
  end

  defp maybe_put_color_state(payload, entity, kelvin, x, y) do
    cond do
      entity.supports_color == true and is_number(x) and is_number(y) ->
        payload
        |> Map.put("color_mode", "xy")
        |> Map.put("color", %{"x" => x, "y" => y})

      entity.supports_temp == true and is_number(kelvin) ->
        payload
        |> Map.put("color_mode", "color_temp")
        |> Map.put("color_temp", round(kelvin))

      is_number(Map.get(payload, "brightness")) ->
        if supported_color_modes(entity) == ["brightness"] do
          Map.put(payload, "color_mode", "brightness")
        else
          payload
        end

      true ->
        payload
    end
  end

  defp maybe_put_kelvin_range(payload, entity) do
    if entity.supports_temp == true do
      {min_kelvin, max_kelvin} = Hueworks.Kelvin.derive_range(entity)

      payload
      |> Map.put("color_temp_kelvin", true)
      |> Map.put("min_kelvin", min_kelvin)
      |> Map.put("max_kelvin", max_kelvin)
    else
      payload
    end
  end

  defp supported_color_modes(entity) do
    cond do
      entity.supports_color == true and entity.supports_temp == true -> ["xy", "color_temp"]
      entity.supports_color == true -> ["xy"]
      entity.supports_temp == true -> ["color_temp"]
      true -> ["brightness"]
    end
  end

  defp entity_export_mode(%{ha_export_mode: mode}) when mode in [:none, :switch, :light], do: mode
  defp entity_export_mode(_entity), do: :none

  defp entity_name(entity), do: entity.display_name || entity.name

  defp room_device(entity) do
    room_id = entity.room_id || "unassigned"

    %{
      "identifiers" => ["hueworks_room_#{room_id}"],
      "name" => "HueWorks #{room_name(entity.room)}",
      "manufacturer" => "HueWorks",
      "model" => "Room Controls"
    }
  end

  defp entity_unique_id(kind, mode, id)
       when kind in [:light, :group] and mode in [:switch, :light] do
    "hueworks_#{kind}_#{id}_#{mode}"
  end

  defp entity_object_id(kind, id) when kind in [:light, :group] and is_integer(id) do
    "hueworks_#{kind}_#{id}"
  end

  defp kind_segment(:light), do: "lights"
  defp kind_segment(:group), do: "groups"

  defp command_export_target(topic, topic_prefix \\ @default_topic_prefix)

  defp command_export_target(topic, topic_prefix)
       when is_binary(topic) and is_binary(topic_prefix) do
    topic
    |> String.split("/", trim: true)
    |> command_export_target(topic_prefix)
  end

  defp command_export_target(topic_levels, topic_prefix)
       when is_list(topic_levels) and is_binary(topic_prefix) do
    prefix_levels = String.split(topic_prefix, "/", trim: true)

    if Enum.take(topic_levels, length(prefix_levels)) == prefix_levels do
      case Enum.drop(topic_levels, length(prefix_levels)) do
        ["lights", id, "switch", "set"] -> parse_command_target(:light, :switch, id)
        ["lights", id, "light", "set"] -> parse_command_target(:light, :light, id)
        ["groups", id, "switch", "set"] -> parse_command_target(:group, :switch, id)
        ["groups", id, "light", "set"] -> parse_command_target(:group, :light, id)
        _ -> nil
      end
    else
      nil
    end
  end

  defp command_export_target(_topic_levels, _topic_prefix), do: nil

  defp parse_command_target(kind, mode, id)
       when kind in [:light, :group] and mode in [:switch, :light] do
    case Integer.parse(id) do
      {parsed, ""} -> %{kind: kind, mode: mode, id: parsed}
      _ -> nil
    end
  end

  defp normalize_power_payload(value) when value in [:on, :off], do: value
  defp normalize_power_payload(value) when value in ["ON", "on"], do: :on
  defp normalize_power_payload(value) when value in ["OFF", "off"], do: :off
  defp normalize_power_payload(_value), do: nil

  defp normalize_export_brightness(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> Util.clamp(round(number), 0, 100)
    end
  end

  defp normalize_export_kelvin(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> round(number)
    end
  end

  defp normalize_export_xy(%{} = color) do
    {normalize_xy_value(Map.get(color, "x")), normalize_xy_value(Map.get(color, "y"))}
  end

  defp normalize_export_xy(_color), do: {nil, nil}

  defp normalize_xy_value(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> Float.round(number, 4)
    end
  end

  defp power_to_mqtt_json(:on), do: "ON"
  defp power_to_mqtt_json(:off), do: "OFF"
  defp power_to_mqtt_json(_value), do: nil

  defp state_power_value(nil), do: nil

  defp state_power_value(state) when is_map(state) do
    case Map.get(state, :power) || Map.get(state, "power") do
      value when value in [:on, "on", "ON", true] -> :on
      value when value in [:off, "off", "OFF", false] -> :off
      _ -> nil
    end
  end

  defp maybe_put_auth(opts, %{username: username, password: password}) when is_binary(username) do
    opts
    |> Keyword.put(:user_name, username)
    |> maybe_put_password(password)
  end

  defp maybe_put_auth(opts, _config), do: opts

  defp maybe_put_password(opts, password) when is_binary(password),
    do: Keyword.put(opts, :password, password)

  defp maybe_put_password(opts, _password), do: opts

  defp room_name(%Room{} = room), do: room.display_name || room.name
  defp room_name(_room), do: "Unknown Room"

  defp scene_name(%Scene{} = scene), do: scene.display_name || scene.name

  defp room_scene_options(scenes) when is_list(scenes) do
    duplicate_counts = Enum.frequencies_by(scenes, &scene_name/1)

    Enum.map(scenes, fn scene ->
      base_name = scene_name(scene)

      label =
        if duplicate_counts[base_name] > 1 do
          "#{base_name} (##{scene.id})"
        else
          base_name
        end

      %{label: label, scene: scene}
    end)
  end

  defp room_select_option_labels(scenes) when is_list(scenes) do
    ["None" | Enum.map(room_scene_options(scenes), & &1.label)]
  end

  defp room_select_state_payload(room_id, scenes) when is_integer(room_id) and is_list(scenes) do
    active_scene_id =
      case ActiveScenes.get_for_room(room_id) do
        %{scene_id: scene_id} -> scene_id
        _ -> nil
      end

    room_scene_options(scenes)
    |> Enum.find_value("None", fn %{label: label, scene: scene} ->
      if scene.id == active_scene_id, do: label, else: nil
    end)
  end

  defp active_scene_name(room_id, scenes) when is_integer(room_id) and is_list(scenes) do
    case room_select_state_payload(room_id, scenes) do
      "None" -> nil
      value -> value
    end
  end

  defp export_enabled?(%{enabled: true, host: host}) when is_binary(host),
    do: String.trim(host) != ""

  defp export_enabled?(_config), do: false

  defp scenes_enabled?(%{scenes_enabled: true}), do: true
  defp scenes_enabled?(_config), do: false

  defp room_selects_enabled?(%{room_selects_enabled: true}), do: true
  defp room_selects_enabled?(_config), do: false

  defp lights_enabled?(%{lights_enabled: true}), do: true
  defp lights_enabled?(_config), do: false

  defp same_config?(nil, _config), do: false
  defp same_config?(left, right), do: left == right

  defp connection_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp connection_alive?(_pid), do: false

  defp normalize_payload(payload) when is_binary(payload), do: String.trim(payload)
  defp normalize_payload(payload), do: IO.iodata_to_binary(payload) |> String.trim()

  defp command_topic_filters do
    [
      "#{@default_topic_prefix}/scenes/+/set",
      "#{@default_topic_prefix}/rooms/+/scene/set",
      "#{@default_topic_prefix}/lights/+/switch/set",
      "#{@default_topic_prefix}/lights/+/light/set",
      "#{@default_topic_prefix}/groups/+/switch/set",
      "#{@default_topic_prefix}/groups/+/light/set"
    ]
  end

  defp tortoise_module do
    case Application.get_env(:hueworks, :ha_export_tortoise_module) do
      nil -> Tortoise
      module -> module
    end
  end

  defp supervisor_module do
    case Application.get_env(:hueworks, :ha_export_tortoise_supervisor_module) do
      nil -> Tortoise.Supervisor
      module -> module
    end
  end

  defp dynamic_supervisor_module do
    case Application.get_env(:hueworks, :ha_export_dynamic_supervisor_module) do
      nil -> DynamicSupervisor
      module -> module
    end
  end

  defp tortoise_supervisor_name do
    case Application.get_env(:hueworks, :ha_export_tortoise_supervisor_name) do
      nil -> Tortoise.Supervisor
      name -> name
    end
  end

  defmodule Handler do
    @moduledoc false

    use Tortoise.Handler

    def init([server, client_id, topic_filters]) do
      subscriptions =
        topic_filters
        |> List.wrap()
        |> Enum.map(&{&1, 0})

      {:ok,
       %{
         server: server,
         client_id: client_id,
         subscriptions: subscriptions,
         subscribed?: false
       }}
    end

    def connection(:up, state) do
      case Tortoise.Connection.subscribe(state.client_id, state.subscriptions) do
        {:ok, _ref} ->
          send(state.server, {:mqtt_connected, state.client_id})
          {:ok, %{state | subscribed?: true}}

        {:error, _reason} ->
          {:ok, %{state | subscribed?: false}}
      end
    end

    def connection(:down, state), do: {:ok, %{state | subscribed?: false}}
    def connection(_status, state), do: {:ok, state}
    def subscription(_status, _topic_filter, state), do: {:ok, state}

    def handle_message(topic_levels, payload, state) do
      send(state.server, {:mqtt_message, topic_levels, payload})
      {:ok, state}
    end

    def terminate(_reason, _state), do: :ok
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp maybe_cast(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, message)

      _ ->
        :ok
    end
  end
end
