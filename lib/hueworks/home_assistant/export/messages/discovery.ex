defmodule Hueworks.HomeAssistant.Export.Messages.Discovery do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeAssistant.Export.Messages.State
  alias Hueworks.HomeAssistant.Export.Messages.Topics
  alias Hueworks.Schemas.{Room, Scene}

  def discovery_payload(%Scene{} = scene, config) do
    room_name = room_name(scene.room)

    %{
      "platform" => "scene",
      "name" => scene_name(scene),
      "unique_id" => "hueworks_scene_#{scene.id}",
      "command_topic" => Topics.command_topic(scene.id),
      "payload_on" => "ON",
      "availability_topic" => Topics.availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => Topics.attributes_topic(scene.id),
      "device" => %{
        "identifiers" => ["hueworks_room_#{scene.room_id}"],
        "name" => "HueWorks #{room_name}",
        "manufacturer" => "HueWorks",
        "model" => "Room Scenes"
      }
    }
    |> maybe_put("configuration_url", configuration_url(config))
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

  def room_select_discovery_payload(%Room{} = room, scenes, config) when is_list(scenes) do
    %{
      "platform" => "select",
      "name" => "Scene",
      "unique_id" => "hueworks_room_scene_select_#{room.id}",
      "command_topic" => Topics.room_select_command_topic(room.id),
      "state_topic" => Topics.room_select_state_topic(room.id),
      "availability_topic" => Topics.availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => Topics.room_select_attributes_topic(room.id),
      "options" => room_select_option_labels(scenes),
      "device" => %{
        "identifiers" => ["hueworks_room_#{room.id}"],
        "name" => "HueWorks #{room_name(room)}",
        "manufacturer" => "HueWorks",
        "model" => "Room Scenes"
      }
    }
    |> maybe_put("configuration_url", configuration_url(config))
  end

  def room_select_attributes_payload(%Room{} = room, scenes) when is_list(scenes) do
    active_scene = ActiveScenes.get_for_room(room.id)

    %{
      "hueworks_managed" => true,
      "hueworks_room_id" => room.id,
      "room_name" => room_name(room),
      "active_scene_id" => active_scene && active_scene.scene_id,
      "active_scene_name" => State.active_scene_name(room.id, scenes),
      "scene_options" => room_select_option_labels(scenes)
    }
  end

  def switch_discovery_payload(kind, entity, config)
      when kind in [:light, :group] and is_map(entity) do
    %{
      "platform" => "switch",
      "name" => entity_name(entity),
      "unique_id" => entity_unique_id(kind, :switch, entity.id),
      "command_topic" => Topics.switch_command_topic(kind, entity.id),
      "state_topic" => Topics.switch_state_topic(kind, entity.id),
      "payload_on" => "ON",
      "payload_off" => "OFF",
      "availability_topic" => Topics.availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => Topics.entity_attributes_topic(kind, entity.id),
      "device" => room_device(entity)
    }
    |> maybe_put("configuration_url", configuration_url(config))
  end

  def light_discovery_payload(kind, entity, config)
      when kind in [:light, :group] and is_map(entity) do
    %{
      "platform" => "light",
      "schema" => "json",
      "name" => entity_name(entity),
      "unique_id" => entity_unique_id(kind, :light, entity.id),
      "command_topic" => Topics.light_command_topic(kind, entity.id),
      "state_topic" => Topics.light_state_topic(kind, entity.id),
      "availability_topic" => Topics.availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => Topics.entity_attributes_topic(kind, entity.id),
      "brightness_scale" => 100,
      "supported_color_modes" => State.supported_color_modes(entity),
      "transition" => false,
      "device" => room_device(entity)
    }
    |> maybe_put("configuration_url", configuration_url(config))
    |> State.maybe_put_kelvin_range(entity)
  end

  def entity_attributes_payload(kind, entity)
      when kind in [:light, :group] and is_map(entity) do
    %{
      "hueworks_managed" => true,
      "hueworks_entity_kind" => Atom.to_string(kind),
      "hueworks_entity_id" => entity.id,
      "hueworks_export_mode" => Atom.to_string(State.entity_export_mode(entity)),
      "hueworks_room_id" => entity.room_id,
      "room_name" => room_name(entity.room),
      "entity_name" => entity_name(entity),
      "source" => to_string(entity.source)
    }
  end

  def room_scene_options(scenes) when is_list(scenes), do: State.room_scene_options(scenes)
  def active_scene_name(room_id, scenes) when is_integer(room_id) and is_list(scenes), do: State.active_scene_name(room_id, scenes)

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

  defp configuration_url(%{configuration_url: configuration_url}), do: configuration_url
  defp configuration_url(_config), do: nil

  defp room_name(%Room{} = room), do: room.display_name || room.name
  defp room_name(_room), do: "Unknown Room"

  defp scene_name(%Scene{} = scene), do: scene.display_name || scene.name

  defp entity_name(entity), do: entity.display_name || entity.name

  defp room_select_option_labels(scenes) when is_list(scenes) do
    scenes
    |> State.room_scene_options()
    |> Enum.map(& &1.label)
    |> then(&["Manual" | &1])
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
