defmodule Hueworks.HomeAssistant.Export.Sync.OccupancySources do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.Runtime

  def publish_all(publish_fun, config) when is_function(publish_fun, 3) do
    if Runtime.export_enabled?(config) do
      Entities.list_occupancy_sources()
      |> Enum.each(fn source ->
        :ok = Publisher.publish_occupancy_source_payloads(publish_fun, source, config)
      end)
    end

    :ok
  end

  def publish_room(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) do
      Entities.list_occupancy_sources_for_room(room_id)
      |> Enum.each(fn source ->
        :ok = Publisher.publish_occupancy_source_payloads(publish_fun, source, config)
      end)
    end

    :ok
  end

  def publish_one(publish_fun, source_id, config)
      when is_function(publish_fun, 3) and is_integer(source_id) do
    if Runtime.export_enabled?(config) do
      Publisher.publish_occupancy_source_payloads(
        publish_fun,
        Entities.fetch_occupancy_source(source_id),
        config
      )
    else
      :ok
    end
  end

  def unpublish_one(publish_fun, source_id, config)
      when is_function(publish_fun, 3) and is_integer(source_id) do
    if Runtime.export_enabled?(config) do
      Publisher.unpublish_occupancy_source_payloads(publish_fun, source_id, config)
    else
      :ok
    end
  end

  def unpublish_all(publish_fun, config) when is_function(publish_fun, 3) do
    Entities.list_occupancy_source_ids()
    |> Enum.each(fn source_id ->
      :ok = Publisher.unpublish_occupancy_source_payloads(publish_fun, source_id, config)
    end)

    :ok
  end
end
