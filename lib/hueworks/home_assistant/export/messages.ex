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

  defmodule AreaSceneOption do
    @moduledoc false

    @enforce_keys [:label, :scene]
    defstruct [:label, :scene]
  end

  defdelegate availability_topic(), to: Topics
  defdelegate command_topic(scene_id), to: Topics
  defdelegate attributes_topic(scene_id), to: Topics
  defdelegate area_select_command_topic(area_id), to: Topics
  defdelegate area_select_state_topic(area_id), to: Topics
  defdelegate area_select_attributes_topic(area_id), to: Topics
  defdelegate entity_attributes_topic(kind, id), to: Topics
  defdelegate presence_input_attributes_topic(id), to: Topics
  defdelegate switch_command_topic(kind, id), to: Topics
  defdelegate presence_input_command_topic(id), to: Topics
  defdelegate switch_state_topic(kind, id), to: Topics
  defdelegate presence_input_state_topic(id), to: Topics
  defdelegate light_command_topic(kind, id), to: Topics
  defdelegate light_state_topic(kind, id), to: Topics
  defdelegate discovery_topic(scene_id, discovery_prefix), to: Topics
  defdelegate area_select_discovery_topic(area_id, discovery_prefix), to: Topics
  defdelegate switch_discovery_topic(kind, id, discovery_prefix), to: Topics
  defdelegate presence_input_discovery_topic(id, discovery_prefix), to: Topics
  defdelegate light_discovery_topic(kind, id, discovery_prefix), to: Topics
  defdelegate command_scene_id(topic_levels, topic_prefix), to: Topics
  defdelegate command_area_id(topic_levels, topic_prefix), to: Topics
  defdelegate command_export_target(topic, topic_prefix), to: Topics

  defdelegate discovery_payload(scene, config), to: Discovery
  defdelegate scene_attributes_payload(scene), to: Discovery
  defdelegate area_select_discovery_payload(area, scenes, config), to: Discovery
  defdelegate area_select_attributes_payload(area, scenes), to: Discovery
  defdelegate switch_discovery_payload(kind, entity, config), to: Discovery
  defdelegate presence_input_discovery_payload(input, config), to: Discovery
  defdelegate light_discovery_payload(kind, entity, config), to: Discovery
  defdelegate entity_attributes_payload(kind, entity), to: Discovery
  defdelegate presence_input_attributes_payload(input), to: Discovery
  defdelegate area_scene_options(scenes), to: Discovery
  defdelegate active_scene_name(area_id, scenes), to: Discovery

  defdelegate entity_export_mode(entity), to: State
  defdelegate normalize_power_payload(value), to: State
  defdelegate normalize_export_brightness(value), to: State
  defdelegate normalize_export_kelvin(value), to: State
  defdelegate normalize_export_xy(color), to: State
  defdelegate area_select_state_payload(area_id, scenes), to: State

  def discovery_topic(scene_id), do: Topics.discovery_topic(scene_id)

  def area_select_discovery_topic(area_id), do: Topics.area_select_discovery_topic(area_id)

  def switch_discovery_topic(kind, id), do: Topics.switch_discovery_topic(kind, id)

  def presence_input_discovery_topic(id), do: Topics.presence_input_discovery_topic(id)

  def light_discovery_topic(kind, id), do: Topics.light_discovery_topic(kind, id)

  def command_scene_id(topic_levels), do: Topics.command_scene_id(topic_levels)

  def command_area_id(topic_levels), do: Topics.command_area_id(topic_levels)

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

  defdelegate presence_input_state_payload(input), to: State
end
