defmodule Hueworks.HomeAssistant.Export.Messages.Topics do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Messages.CommandTarget

  @default_discovery_prefix "homeassistant"
  @default_topic_prefix "hueworks/ha_export"

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

  defp kind_segment(:light), do: "lights"
  defp kind_segment(:group), do: "groups"

  defp entity_object_id(kind, id) when kind in [:light, :group] and is_integer(id) do
    "hueworks_#{kind}_#{id}"
  end

  defp parse_command_target(kind, mode, id)
       when kind in [:light, :group] and mode in [:switch, :light] do
    case Integer.parse(id) do
      {parsed, ""} -> %CommandTarget{kind: kind, mode: mode, id: parsed}
      _ -> nil
    end
  end
end
