defmodule Hueworks.HomeAssistant.Export.Messages do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Messages.Discovery
  alias Hueworks.HomeAssistant.Export.Messages.State
  alias Hueworks.HomeAssistant.Export.Messages.Topics

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

  defdelegate availability_topic(), to: Topics
  defdelegate command_topic(scene_id), to: Topics
  defdelegate attributes_topic(scene_id), to: Topics
  defdelegate room_select_command_topic(room_id), to: Topics
  defdelegate room_select_state_topic(room_id), to: Topics
  defdelegate room_select_attributes_topic(room_id), to: Topics
  defdelegate entity_attributes_topic(kind, id), to: Topics
  defdelegate switch_command_topic(kind, id), to: Topics
  defdelegate switch_state_topic(kind, id), to: Topics
  defdelegate light_command_topic(kind, id), to: Topics
  defdelegate light_state_topic(kind, id), to: Topics
  defdelegate discovery_topic(scene_id, discovery_prefix), to: Topics
  defdelegate room_select_discovery_topic(room_id, discovery_prefix), to: Topics
  defdelegate switch_discovery_topic(kind, id, discovery_prefix), to: Topics
  defdelegate light_discovery_topic(kind, id, discovery_prefix), to: Topics
  defdelegate command_scene_id(topic_levels, topic_prefix), to: Topics
  defdelegate command_room_id(topic_levels, topic_prefix), to: Topics
  defdelegate command_export_target(topic, topic_prefix), to: Topics

  defdelegate discovery_payload(scene, config), to: Discovery
  defdelegate scene_attributes_payload(scene), to: Discovery
  defdelegate room_select_discovery_payload(room, scenes, config), to: Discovery
  defdelegate room_select_attributes_payload(room, scenes), to: Discovery
  defdelegate switch_discovery_payload(kind, entity, config), to: Discovery
  defdelegate light_discovery_payload(kind, entity, config), to: Discovery
  defdelegate entity_attributes_payload(kind, entity), to: Discovery
  defdelegate room_scene_options(scenes), to: Discovery
  defdelegate active_scene_name(room_id, scenes), to: Discovery

  defdelegate entity_export_mode(entity), to: State
  defdelegate normalize_power_payload(value), to: State
  defdelegate normalize_export_brightness(value), to: State
  defdelegate normalize_export_kelvin(value), to: State
  defdelegate normalize_export_xy(color), to: State
  defdelegate room_select_state_payload(room_id, scenes), to: State

  def discovery_topic(scene_id), do: Topics.discovery_topic(scene_id)

  def room_select_discovery_topic(room_id), do: Topics.room_select_discovery_topic(room_id)

  def switch_discovery_topic(kind, id), do: Topics.switch_discovery_topic(kind, id)

  def light_discovery_topic(kind, id), do: Topics.light_discovery_topic(kind, id)

  def command_scene_id(topic_levels), do: Topics.command_scene_id(topic_levels)

  def command_room_id(topic_levels), do: Topics.command_room_id(topic_levels)

  def command_export_target(topic), do: Topics.command_export_target(topic)

  def light_state_payload(kind, entity) when kind in [:light, :group] do
    State.light_state_payload(kind, entity)
  end

  def light_state_payload(entity, state) when is_map(entity) and is_map(state) do
    State.light_state_payload(entity, state)
  end

  def switch_state_payload(kind, id) when kind in [:light, :group] and is_integer(id) do
    State.switch_state_payload(kind, id)
  end

  def switch_state_payload(state) when is_map(state) do
    State.switch_state_payload(state)
  end
end
