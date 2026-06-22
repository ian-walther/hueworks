defmodule Hueworks.HomeAssistant.Export.Sync.PresenceInputs do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.Runtime

  def publish_all(publish_fun, config) when is_function(publish_fun, 3) do
    if Runtime.export_enabled?(config) do
      Entities.list_presence_inputs()
      |> Enum.each(fn input ->
        :ok = Publisher.publish_presence_input_payloads(publish_fun, input, config)
      end)
    end

    :ok
  end

  def publish_room(publish_fun, room_id, config)
      when is_function(publish_fun, 3) and is_integer(room_id) do
    if Runtime.export_enabled?(config) do
      Entities.list_presence_inputs_for_room(room_id)
      |> Enum.each(fn input ->
        :ok = Publisher.publish_presence_input_payloads(publish_fun, input, config)
      end)
    end

    :ok
  end

  def publish_one(publish_fun, input_id, config)
      when is_function(publish_fun, 3) and is_integer(input_id) do
    if Runtime.export_enabled?(config) do
      Publisher.publish_presence_input_payloads(
        publish_fun,
        Entities.fetch_presence_input(input_id),
        config
      )
    else
      :ok
    end
  end

  def unpublish_one(publish_fun, input_id, config)
      when is_function(publish_fun, 3) and is_integer(input_id) do
    if Runtime.export_enabled?(config) do
      Publisher.unpublish_presence_input_payloads(publish_fun, input_id, config)
    else
      :ok
    end
  end
end
