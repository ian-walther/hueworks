defmodule Hueworks.HomeAssistant.Export.Sync do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.Schemas.Scene

  def publish_all_entities(publish_fun, config) when is_function(publish_fun, 3) do
    if Runtime.export_enabled?(config) do
      if Runtime.scenes_enabled?(config) do
        Entities.list_exportable_scenes()
        |> Enum.each(fn scene ->
          :ok = Publisher.publish_scene_payloads(publish_fun, scene, config)
        end)
      end

      if Runtime.room_selects_enabled?(config) do
        Entities.list_rooms()
        |> Enum.each(fn room ->
          :ok = Publisher.publish_room_select_payloads(publish_fun, room, config)
        end)
      end

      if Runtime.lights_enabled?(config) do
        Entities.list_exportable_lights()
        |> Enum.each(fn light ->
          :ok = Publisher.sync_entity_payloads(publish_fun, :light, light, config)
        end)

        Entities.list_exportable_groups()
        |> Enum.each(fn group ->
          :ok = Publisher.sync_entity_payloads(publish_fun, :group, group, config)
        end)
      end
    end

    :ok
  end

  def publish_room_entities(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) do
      if Runtime.scenes_enabled?(config) do
        Entities.list_exportable_scenes_for_room(room_id)
        |> Enum.each(fn scene ->
          :ok = Publisher.publish_scene_payloads(publish_fun, scene, config)
        end)
      end

      if Runtime.room_selects_enabled?(config) do
        :ok = Publisher.publish_room_select_payloads(publish_fun, room_id, config)
      end

      if Runtime.lights_enabled?(config) do
        Entities.list_exportable_lights_for_room(room_id)
        |> Enum.each(fn light ->
          :ok = Publisher.sync_entity_payloads(publish_fun, :light, light, config)
        end)

        Entities.list_exportable_groups_for_room(room_id)
        |> Enum.each(fn group ->
          :ok = Publisher.sync_entity_payloads(publish_fun, :group, group, config)
        end)
      end
    end

    :ok
  end

  def publish_scene(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    if Runtime.export_enabled?(config) do
      case Entities.exportable_scene(scene_id) do
        %Scene{} = scene ->
          if Runtime.scenes_enabled?(config) do
            :ok = Publisher.publish_scene_payloads(publish_fun, scene, config)
          end

          if Runtime.room_selects_enabled?(config) do
            :ok = Publisher.publish_room_select_payloads(publish_fun, scene.room_id, config)
          end

        nil ->
          :ok
      end
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

      if Runtime.scenes_enabled?(config) do
        :ok = Publisher.unpublish_scene_payloads(publish_fun, scene_id, config)
      end

      if is_integer(room_id) and Runtime.room_selects_enabled?(config) do
        :ok = Publisher.publish_room_select_payloads(publish_fun, room_id, config)
      end
    end

    :ok
  end

  def publish_room_select(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) and Runtime.room_selects_enabled?(config) do
      Publisher.publish_room_select_payloads(publish_fun, room_id, config)
    else
      :ok
    end
  end

  def publish_entity(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    if Runtime.export_enabled?(config) and Runtime.lights_enabled?(config) do
      Publisher.sync_entity_payloads(publish_fun, kind, Entities.fetch_entity(kind, id), config)
    else
      :ok
    end
  end

  def unpublish_entity(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    if Runtime.export_enabled?(config) and Runtime.lights_enabled?(config) do
      Publisher.unpublish_entity_payloads(publish_fun, kind, id, config)
    else
      :ok
    end
  end

  def unpublish_room_select(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) and Runtime.room_selects_enabled?(config) do
      Publisher.unpublish_room_select_payloads(publish_fun, room_id, config)
    else
      :ok
    end
  end

  def unpublish_all_scenes(publish_fun, config) when is_function(publish_fun, 3) do
    Entities.list_exportable_scenes()
    |> Enum.each(fn scene ->
      :ok = Publisher.unpublish_scene_payloads(publish_fun, scene.id, config)
    end)

    :ok
  end

  def unpublish_all_room_selects(publish_fun, config) when is_function(publish_fun, 3) do
    Entities.list_rooms()
    |> Enum.each(fn room ->
      :ok = Publisher.unpublish_room_select_payloads(publish_fun, room.id, config)
    end)

    :ok
  end

  def unpublish_all_light_entities(publish_fun, config) when is_function(publish_fun, 3) do
    Entities.list_controllable_light_ids()
    |> Enum.each(fn light_id ->
      :ok = Publisher.unpublish_entity_payloads(publish_fun, :light, light_id, config)
    end)

    Entities.list_controllable_group_ids()
    |> Enum.each(fn group_id ->
      :ok = Publisher.unpublish_entity_payloads(publish_fun, :group, group_id, config)
    end)

    :ok
  end
end
