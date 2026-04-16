defmodule Hueworks.HomeAssistant.Export.Messages do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.State
  alias Hueworks.Kelvin
  alias Hueworks.Schemas.{Room, Scene}
  alias Hueworks.Util

  @default_discovery_prefix "homeassistant"
  @default_topic_prefix "hueworks/ha_export"

  defmodule CommandTarget do
    @moduledoc false

    @enforce_keys [:kind, :mode, :id]
    defstruct [:kind, :mode, :id]
  end

  defmodule RoomSceneOption do
    @moduledoc false

    @enforce_keys [:label, :scene]
    defstruct [:label, :scene]
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

  def command_export_target(topic, topic_prefix \\ @default_topic_prefix)

  def command_export_target(topic, topic_prefix)
      when is_binary(topic) and is_binary(topic_prefix) do
    topic
    |> String.split("/", trim: true)
    |> command_export_target(topic_prefix)
  end

  def command_export_target(topic_levels, topic_prefix)
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

  def command_export_target(_topic_levels, _topic_prefix), do: nil

  def discovery_payload(%Scene{} = scene, config) do
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
    |> maybe_put("configuration_url", configuration_url(config))
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

  def switch_discovery_payload(kind, entity, config)
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
    |> maybe_put("configuration_url", configuration_url(config))
  end

  def light_discovery_payload(kind, entity, config)
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
    |> maybe_put("configuration_url", configuration_url(config))
    |> maybe_put_kelvin_range(entity)
  end

  def entity_attributes_payload(kind, entity)
      when kind in [:light, :group] and is_map(entity) do
    %{
      "hueworks_managed" => true,
      "hueworks_entity_kind" => Atom.to_string(kind),
      "hueworks_entity_id" => entity.id,
      "hueworks_export_mode" => Atom.to_string(entity_export_mode(entity)),
      "hueworks_room_id" => entity.room_id,
      "room_name" => room_name(entity.room),
      "entity_name" => entity_name(entity),
      "source" => to_string(entity.source)
    }
  end

  def light_state_payload(kind, entity) when kind in [:light, :group] and is_map(entity) do
    light_state_payload(entity, State.get(kind, entity.id) || %{})
  end

  def light_state_payload(entity, state) when is_map(entity) and is_map(state) do
    power = state_power_value(state)

    brightness =
      state
      |> Map.get(:brightness)
      |> Kernel.||(Map.get(state, "brightness"))
      |> normalize_export_brightness()

    kelvin =
      state
      |> Map.get(:kelvin)
      |> Kernel.||(Map.get(state, "kelvin"))
      |> Kernel.||(Map.get(state, :temperature))
      |> Kernel.||(Map.get(state, "temperature"))
      |> normalize_export_kelvin()

    x =
      state
      |> Map.get(:x)
      |> Kernel.||(Map.get(state, "x"))
      |> normalize_xy_value()

    y =
      state
      |> Map.get(:y)
      |> Kernel.||(Map.get(state, "y"))
      |> normalize_xy_value()

    %{"state" => power_to_mqtt_json(power)}
    |> maybe_put("brightness", brightness)
    |> maybe_put_color_state(entity, kelvin, x, y)
  end

  def switch_state_payload(kind, id) when kind in [:light, :group] and is_integer(id) do
    switch_state_payload(State.get(kind, id) || %{})
  end

  def switch_state_payload(state) when is_map(state) do
    case state_power_value(state) do
      :on -> "ON"
      :off -> "OFF"
      _ -> "None"
    end
  end

  def entity_export_mode(%{ha_export_mode: mode}) when mode in [:none, :switch, :light], do: mode
  def entity_export_mode(_entity), do: :none

  def normalize_power_payload(value) when value in [:on, :off], do: value
  def normalize_power_payload(value) when value in ["ON", "on"], do: :on
  def normalize_power_payload(value) when value in ["OFF", "off"], do: :off
  def normalize_power_payload(_value), do: nil

  def normalize_export_brightness(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> Util.clamp(round(number), 0, 100)
    end
  end

  def normalize_export_kelvin(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> round(number)
    end
  end

  def normalize_export_xy(%{} = color) do
    {normalize_xy_value(Map.get(color, "x")), normalize_xy_value(Map.get(color, "y"))}
  end

  def normalize_export_xy(_color), do: {nil, nil}

  def room_select_state_payload(room_id, scenes) when is_integer(room_id) and is_list(scenes) do
    active_scene_id =
      case ActiveScenes.get_for_room(room_id) do
        %{scene_id: scene_id} -> scene_id
        _ -> nil
      end

    scenes
    |> room_scene_options()
    |> Enum.find_value("Manual", fn %RoomSceneOption{label: label, scene: scene} ->
      if scene.id == active_scene_id, do: label, else: nil
    end)
  end

  def active_scene_name(room_id, scenes) when is_integer(room_id) and is_list(scenes) do
    case room_select_state_payload(room_id, scenes) do
      "Manual" -> nil
      value -> value
    end
  end

  def room_scene_options(scenes) when is_list(scenes) do
    duplicate_counts = Enum.frequencies_by(scenes, &scene_name/1)

    Enum.map(scenes, fn scene ->
      base_name = scene_name(scene)

      label =
        if duplicate_counts[base_name] > 1 do
          "#{base_name} (##{scene.id})"
        else
          base_name
        end

      %RoomSceneOption{label: label, scene: scene}
    end)
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
      {min_kelvin, max_kelvin} = Kelvin.derive_range(entity)

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

  defp configuration_url(%{configuration_url: configuration_url}), do: configuration_url
  defp configuration_url(_config), do: nil

  defp kind_segment(:light), do: "lights"
  defp kind_segment(:group), do: "groups"

  defp parse_command_target(kind, mode, id)
       when kind in [:light, :group] and mode in [:switch, :light] do
    case Integer.parse(id) do
      {parsed, ""} -> %CommandTarget{kind: kind, mode: mode, id: parsed}
      _ -> nil
    end
  end

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

  defp room_name(%Room{} = room), do: room.display_name || room.name
  defp room_name(_room), do: "Unknown Room"

  defp scene_name(%Scene{} = scene), do: scene.display_name || scene.name

  defp entity_name(entity), do: entity.display_name || entity.name

  defp room_select_option_labels(scenes) when is_list(scenes) do
    scenes
    |> room_scene_options()
    |> Enum.map(& &1.label)
    |> then(&["Manual" | &1])
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
