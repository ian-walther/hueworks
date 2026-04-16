defmodule Hueworks.HomeAssistant.Export.Sync.Rooms do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.Runtime

  def publish_all_selects(publish_fun, config) when is_function(publish_fun, 3) do
    if Runtime.export_enabled?(config) and Runtime.room_selects_enabled?(config) do
      Entities.list_rooms()
      |> Enum.each(fn room ->
        :ok = Publisher.publish_room_select_payloads(publish_fun, room, config)
      end)
    end

    :ok
  end

  def publish_select(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) and Runtime.room_selects_enabled?(config) do
      Publisher.publish_room_select_payloads(publish_fun, room_id, config)
    else
      :ok
    end
  end

  def unpublish_select(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) and Runtime.room_selects_enabled?(config) do
      Publisher.unpublish_room_select_payloads(publish_fun, room_id, config)
    else
      :ok
    end
  end

  def unpublish_all_selects(publish_fun, config) when is_function(publish_fun, 3) do
    Entities.list_rooms()
    |> Enum.each(fn room ->
      :ok = Publisher.unpublish_room_select_payloads(publish_fun, room.id, config)
    end)

    :ok
  end
end
