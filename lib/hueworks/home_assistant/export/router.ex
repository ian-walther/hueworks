defmodule Hueworks.HomeAssistant.Export.Router do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.HomeAssistant.Export.Messages.CommandTarget
  alias Hueworks.HomeAssistant.Export.Router.EntityCommands
  alias Hueworks.HomeAssistant.Export.Router.SceneCommands

  def dispatch(topic_levels, payload, config, publish_fun)
      when is_list(topic_levels) and is_function(publish_fun, 3) do
    normalized_payload = Hueworks.HomeAssistant.Export.Runtime.normalize_payload(payload)

    case {Messages.command_scene_id(topic_levels), Messages.command_room_id(topic_levels),
          Messages.command_export_target(topic_levels), normalized_payload} do
      {scene_id, _room_id, _entity_command, "ON"} when is_integer(scene_id) ->
        SceneCommands.activate_scene(scene_id)

      {_scene_id, room_id, _entity_command, option_label} when is_integer(room_id) ->
        SceneCommands.handle_room_select_command(room_id, option_label)

      {_scene_id, _room_id, %CommandTarget{kind: kind, id: id, mode: :switch}, command_payload} ->
        EntityCommands.handle_switch_command(kind, id, command_payload, config, publish_fun)

      {_scene_id, _room_id, %CommandTarget{kind: kind, id: id, mode: :light}, command_payload} ->
        EntityCommands.handle_light_command(kind, id, command_payload, config, publish_fun)

      _ ->
        :ok
    end
  end
end
