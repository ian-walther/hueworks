defmodule Hueworks.HomeAssistant.Export.Messages.Discovery do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeAssistant.Export.Messages.State
  alias Hueworks.HomeAssistant.Export.Messages.Topics
  alias Hueworks.PublishedIdentity
  alias Hueworks.Schemas.{Group, Light, PresenceInput, Area, Scene}

  def discovery_payload(%Scene{} = scene, config) do
    area_name = area_name(scene.area)

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
        "identifiers" => [area_device_identifier(scene.area)],
        "name" => "HueWorks #{area_name}",
        "manufacturer" => "HueWorks",
        "model" => "Area Scenes"
      }
    }
    |> maybe_put("configuration_url", configuration_url(config))
  end

  def scene_attributes_payload(%Scene{} = scene) do
    %{
      "hueworks_managed" => true,
      "hueworks_scene_id" => scene.id,
      "hueworks_area_id" => scene.area_id,
      "area_name" => area_name(scene.area),
      "scene_name" => scene_name(scene)
    }
  end

  def area_select_discovery_payload(%Area{} = area, scenes, config) when is_list(scenes) do
    %{
      "platform" => "select",
      "name" => "Scene",
      "unique_id" => PublishedIdentity.fetch!(area, :ha_scene_select_identifier),
      "command_topic" => Topics.area_select_command_topic(area.id),
      "state_topic" => Topics.area_select_state_topic(area.id),
      "availability_topic" => Topics.availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => Topics.area_select_attributes_topic(area.id),
      "options" => area_select_option_labels(scenes),
      "device" => %{
        "identifiers" => [area_device_identifier(area)],
        "name" => "HueWorks #{area_name(area)}",
        "manufacturer" => "HueWorks",
        "model" => "Area Scenes"
      }
    }
    |> maybe_put("configuration_url", configuration_url(config))
  end

  def area_select_attributes_payload(%Area{} = area, scenes) when is_list(scenes) do
    active_scene = ActiveScenes.get_for_area(area.id)

    %{
      "hueworks_managed" => true,
      "hueworks_area_id" => area.id,
      "area_name" => area_name(area),
      "active_scene_id" => active_scene && active_scene.scene_id,
      "active_scene_name" => State.active_scene_name(area.id, scenes),
      "scene_options" => area_select_option_labels(scenes)
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
      "device" => area_device(entity)
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
      "device" => area_device(entity)
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
      "hueworks_area_id" => entity.area_id,
      "area_name" => area_name(entity.area),
      "entity_name" => entity_name(entity),
      "source" => to_string(entity.source)
    }
  end

  def presence_input_discovery_payload(%PresenceInput{} = input, config) do
    %{
      "platform" => "switch",
      "name" => presence_input_name(input),
      "unique_id" => "hueworks_presence_input_#{input.id}_switch",
      "command_topic" => Topics.presence_input_command_topic(input.id),
      "state_topic" => Topics.presence_input_state_topic(input.id),
      "payload_on" => "ON",
      "payload_off" => "OFF",
      "availability_topic" => Topics.availability_topic(),
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "json_attributes_topic" => Topics.presence_input_attributes_topic(input.id),
      "device" => %{
        "identifiers" => [area_device_identifier(input.area)],
        "name" => "HueWorks #{area_name(input.area)}",
        "manufacturer" => "HueWorks",
        "model" => "Presence Inputs"
      }
    }
    |> maybe_put("configuration_url", configuration_url(config))
  end

  def presence_input_attributes_payload(%PresenceInput{} = input) do
    %{
      "hueworks_managed" => true,
      "hueworks_entity_kind" => "presence_input",
      "hueworks_presence_input_id" => input.id,
      "hueworks_area_id" => input.area_id,
      "area_name" => area_name(input.area),
      "presence_input_name" => presence_input_name(input)
    }
  end

  def area_scene_options(scenes) when is_list(scenes), do: State.area_scene_options(scenes)

  def active_scene_name(area_id, scenes) when is_integer(area_id) and is_list(scenes),
    do: State.active_scene_name(area_id, scenes)

  defp area_device(entity) do
    %{
      "identifiers" => [area_device_identifier(entity.area)],
      "name" => "HueWorks #{area_name(entity.area)}",
      "manufacturer" => "HueWorks",
      "model" => "Area Controls"
    }
  end

  defp entity_unique_id(kind, mode, id)
       when kind in [:light, :group] and mode in [:switch, :light] do
    "hueworks_#{kind}_#{id}_#{mode}"
  end

  defp configuration_url(%{configuration_url: configuration_url}), do: configuration_url
  defp configuration_url(_config), do: nil

  defp area_name(%Area{} = area), do: area.display_name || area.name
  defp area_name(_area), do: "Unknown Area"

  defp area_device_identifier(%Area{} = area),
    do: PublishedIdentity.fetch!(area, :ha_device_identifier)

  defp area_device_identifier(_area), do: "hueworks_area_unassigned"

  defp scene_name(%Scene{} = scene), do: scene.display_name || scene.name

  defp entity_name(%Light{display_name: display_name}), do: display_name
  defp entity_name(%Group{display_name: display_name}), do: display_name
  defp entity_name(entity), do: entity.display_name || entity.name

  defp presence_input_name(%PresenceInput{} = input), do: input.name

  defp area_select_option_labels(scenes) when is_list(scenes) do
    scenes
    |> State.area_scene_options()
    |> Enum.map(& &1.label)
    |> then(&["Manual" | &1])
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
