defmodule Hueworks.HomeAssistant.Export.Sync do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.HomeAssistant.Export.Sync.Entities, as: EntitySync
  alias Hueworks.HomeAssistant.Export.Sync.PresenceInputs, as: PresenceInputSync
  alias Hueworks.HomeAssistant.Export.Sync.Areas, as: AreaSync
  alias Hueworks.HomeAssistant.Export.Sync.Scenes, as: SceneSync
  alias Hueworks.Schemas.Scene

  def publish_all_entities(publish_fun, config) when is_function(publish_fun, 3) do
    :ok = SceneSync.publish_all(publish_fun, config)
    :ok = AreaSync.publish_all_selects(publish_fun, config)
    :ok = PresenceInputSync.publish_all(publish_fun, config)
    :ok = EntitySync.publish_all(publish_fun, config)

    :ok
  end

  def publish_area_entities(publish_fun, area_id, config)
      when is_function(publish_fun, 3) and is_integer(area_id) do
    :ok = SceneSync.publish_area(publish_fun, area_id, config)
    :ok = AreaSync.publish_select(publish_fun, area_id, config)
    :ok = PresenceInputSync.publish_area(publish_fun, area_id, config)
    :ok = EntitySync.publish_area(publish_fun, area_id, config)

    :ok
  end

  def publish_scene(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    case SceneSync.publish_one(publish_fun, scene_id, config) do
      {:ok, %Scene{} = scene} ->
        if Runtime.area_selects_enabled?(config) do
          :ok = AreaSync.publish_select(publish_fun, scene.area_id, config)
        end

      :ok ->
        :ok
    end

    :ok
  end

  def unpublish_scene(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    if Runtime.export_enabled?(config) do
      area_id =
        case Entities.exportable_scene(scene_id) do
          %Scene{} = scene -> scene.area_id
          nil -> nil
        end

      :ok = SceneSync.unpublish_one(publish_fun, scene_id, config)

      if is_integer(area_id) and Runtime.area_selects_enabled?(config) do
        :ok = AreaSync.publish_select(publish_fun, area_id, config)
      end
    end

    :ok
  end

  def publish_area_select(publish_fun, area_id, config)
      when is_function(publish_fun, 3) and is_integer(area_id) do
    AreaSync.publish_select(publish_fun, area_id, config)
  end

  def publish_entity(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    EntitySync.publish_one(publish_fun, kind, id, config)
  end

  def publish_groups_for_light(publish_fun, light_id, config)
      when is_function(publish_fun, 3) and is_integer(light_id) do
    EntitySync.publish_groups_for_light(publish_fun, light_id, config)
  end

  def publish_presence_input(publish_fun, input_id, config)
      when is_function(publish_fun, 3) and is_integer(input_id) do
    PresenceInputSync.publish_one(publish_fun, input_id, config)
  end

  def publish_presence_inputs_for_area(publish_fun, area_id, config)
      when is_function(publish_fun, 3) and is_integer(area_id) do
    PresenceInputSync.publish_area(publish_fun, area_id, config)
  end

  def unpublish_entity(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    EntitySync.unpublish_one(publish_fun, kind, id, config)
  end

  def unpublish_presence_input(publish_fun, input_id, config)
      when is_function(publish_fun, 3) and is_integer(input_id) do
    PresenceInputSync.unpublish_one(publish_fun, input_id, config)
  end

  def unpublish_area_select(publish_fun, area_id, identifier, config)
      when is_function(publish_fun, 3) and is_integer(area_id) and is_binary(identifier) do
    AreaSync.unpublish_select(publish_fun, area_id, identifier, config)
  end

  def unpublish_all_scenes(publish_fun, config) when is_function(publish_fun, 3) do
    SceneSync.unpublish_all(publish_fun, config)
  end

  def unpublish_all_area_selects(publish_fun, config) when is_function(publish_fun, 3) do
    AreaSync.unpublish_all_selects(publish_fun, config)
  end

  def unpublish_all_light_entities(publish_fun, config) when is_function(publish_fun, 3) do
    EntitySync.unpublish_all(publish_fun, config)
  end
end
