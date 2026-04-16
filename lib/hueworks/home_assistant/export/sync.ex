defmodule Hueworks.HomeAssistant.Export.Sync do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.HomeAssistant.Export.Sync.Entities, as: EntitySync
  alias Hueworks.HomeAssistant.Export.Sync.Rooms, as: RoomSync
  alias Hueworks.HomeAssistant.Export.Sync.Scenes, as: SceneSync
  alias Hueworks.Schemas.Scene

  def publish_all_entities(publish_fun, config) when is_function(publish_fun, 3) do
    :ok = SceneSync.publish_all(publish_fun, config)
    :ok = RoomSync.publish_all_selects(publish_fun, config)
    :ok = EntitySync.publish_all(publish_fun, config)

    :ok
  end

  def publish_room_entities(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    :ok = SceneSync.publish_room(publish_fun, room_id, config)
    :ok = RoomSync.publish_select(publish_fun, room_id, config)
    :ok = EntitySync.publish_room(publish_fun, room_id, config)

    :ok
  end

  def publish_scene(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    case SceneSync.publish_one(publish_fun, scene_id, config) do
      {:ok, %Scene{} = scene} ->
        if Runtime.room_selects_enabled?(config) do
          :ok = RoomSync.publish_select(publish_fun, scene.room_id, config)
        end

      :ok ->
        :ok
    end

    :ok
  end

  def unpublish_scene(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    if Runtime.export_enabled?(config) do
      room_id =
        case Entities.exportable_scene(scene_id) do
          %Scene{} = scene -> scene.room_id
          nil -> nil
        end

      :ok = SceneSync.unpublish_one(publish_fun, scene_id, config)

      if is_integer(room_id) and Runtime.room_selects_enabled?(config) do
        :ok = RoomSync.publish_select(publish_fun, room_id, config)
      end
    end

    :ok
  end

  def publish_room_select(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    RoomSync.publish_select(publish_fun, room_id, config)
  end

  def publish_entity(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    EntitySync.publish_one(publish_fun, kind, id, config)
  end

  def unpublish_entity(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    EntitySync.unpublish_one(publish_fun, kind, id, config)
  end

  def unpublish_room_select(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    RoomSync.unpublish_select(publish_fun, room_id, config)
  end

  def unpublish_all_scenes(publish_fun, config) when is_function(publish_fun, 3) do
    SceneSync.unpublish_all(publish_fun, config)
  end

  def unpublish_all_room_selects(publish_fun, config) when is_function(publish_fun, 3) do
    RoomSync.unpublish_all_selects(publish_fun, config)
  end

  def unpublish_all_light_entities(publish_fun, config) when is_function(publish_fun, 3) do
    EntitySync.unpublish_all(publish_fun, config)
  end
end
