defmodule Hueworks.HomeAssistant.Export.Sync.Entities do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.Runtime

  def publish_all(publish_fun, config) when is_function(publish_fun, 3) do
    if Runtime.export_enabled?(config) and Runtime.lights_enabled?(config) do
      publish_each(publish_fun, :light, Entities.list_exportable_lights(), config)
      publish_each(publish_fun, :group, Entities.list_exportable_groups(), config)
    end

    :ok
  end

  def publish_room(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) and Runtime.lights_enabled?(config) do
      publish_each(publish_fun, :light, Entities.list_exportable_lights_for_room(room_id), config)
      publish_each(publish_fun, :group, Entities.list_exportable_groups_for_room(room_id), config)
    end

    :ok
  end

  def publish_one(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    if Runtime.export_enabled?(config) and Runtime.lights_enabled?(config) do
      Publisher.sync_entity_payloads(publish_fun, kind, Entities.fetch_entity(kind, id), config)
    else
      :ok
    end
  end

  def unpublish_one(publish_fun, kind, id, config)
      when is_function(publish_fun, 3) and kind in [:light, :group] and is_integer(id) do
    if Runtime.export_enabled?(config) and Runtime.lights_enabled?(config) do
      Publisher.unpublish_entity_payloads(publish_fun, kind, id, config)
    else
      :ok
    end
  end

  def unpublish_all(publish_fun, config) when is_function(publish_fun, 3) do
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

  defp publish_each(publish_fun, kind, entities, config) do
    entities
    |> Enum.each(fn entity ->
      :ok = Publisher.sync_entity_payloads(publish_fun, kind, entity, config)
    end)
  end
end
