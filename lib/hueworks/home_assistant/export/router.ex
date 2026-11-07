defmodule Hueworks.HomeAssistant.Export.Router do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Config
  alias Hueworks.HomeAssistant.Export.Messages.CommandTarget
  alias Hueworks.HomeAssistant.Export.Router.EntityCommands
  alias Hueworks.HomeAssistant.Export.Router.SceneCommands
  alias Hueworks.HomeAssistant.Export.Router.SettingCommands
  alias Hueworks.HomeAssistant.Export.ServerState

  def dispatch(topic_levels, payload, %ServerState{} = state, publish_fun)
      when is_list(topic_levels) and is_function(publish_fun, 3) do
    case Messages.command_setting_field(topic_levels) do
      nil -> dispatch_entity_command(topic_levels, payload, state.config, publish_fun)
      field -> SettingCommands.handle_command(field, payload, state, publish_fun)
    end
  end

  defp dispatch_entity_command(topic_levels, payload, config, publish_fun) do
    normalized_payload = Config.normalize_payload(payload)

    case {Messages.command_scene_id(topic_levels), Messages.command_area_id(topic_levels),
          Messages.command_export_target(topic_levels), normalized_payload} do
      {scene_id, _area_id, _entity_command, command_payload} when is_integer(scene_id) ->
        SceneCommands.handle_scene_command(scene_id, command_payload)

      {_scene_id, area_id, _entity_command, option_label} when is_integer(area_id) ->
        SceneCommands.handle_area_select_command(area_id, option_label)

      {_scene_id, _area_id, %CommandTarget{kind: kind, id: id, mode: :switch}, command_payload} ->
        EntityCommands.handle_switch_command(kind, id, command_payload, config, publish_fun)

      {_scene_id, _area_id, %CommandTarget{kind: kind, id: id, mode: :light}, command_payload} ->
        EntityCommands.handle_light_command(kind, id, command_payload, config, publish_fun)

      _ ->
        :ok
    end
  end
end
