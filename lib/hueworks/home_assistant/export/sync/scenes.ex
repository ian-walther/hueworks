defmodule Hueworks.HomeAssistant.Export.Sync.Scenes do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.Runtime
  alias Hueworks.Schemas.Scene

  def publish_all(publish_fun, config) when is_function(publish_fun, 3) do
    if Runtime.export_enabled?(config) and Runtime.scenes_enabled?(config) do
      Entities.list_exportable_scenes()
      |> Enum.each(fn scene ->
        :ok = Publisher.publish_scene_payloads(publish_fun, scene, config)
      end)
    end

    :ok
  end

  def publish_room(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) and Runtime.scenes_enabled?(config) do
      Entities.list_exportable_scenes_for_room(room_id)
      |> Enum.each(fn scene ->
        :ok = Publisher.publish_scene_payloads(publish_fun, scene, config)
      end)
    end

    :ok
  end

  def publish_one(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    if Runtime.export_enabled?(config) do
      case Entities.exportable_scene(scene_id) do
        %Scene{} = scene ->
          if Runtime.scenes_enabled?(config) do
            :ok = Publisher.publish_scene_payloads(publish_fun, scene, config)
          end

          {:ok, scene}

        nil ->
          :ok
      end
    else
      :ok
    end
  end

  def unpublish_one(publish_fun, scene_id, config)
      when is_function(publish_fun, 3) and is_integer(scene_id) do
    if Runtime.export_enabled?(config) and Runtime.scenes_enabled?(config) do
      :ok = Publisher.unpublish_scene_payloads(publish_fun, scene_id, config)
    end

    :ok
  end

  def unpublish_all(publish_fun, config) when is_function(publish_fun, 3) do
    Entities.list_exportable_scenes()
    |> Enum.each(fn scene ->
      :ok = Publisher.unpublish_scene_payloads(publish_fun, scene.id, config)
    end)

    :ok
  end
end
