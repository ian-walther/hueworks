defmodule Hueworks.HomeAssistant.Export.Sync.Areas do
  @moduledoc false

  alias Hueworks.HomeAssistant.Export.Entities
  alias Hueworks.HomeAssistant.Export.Publisher
  alias Hueworks.HomeAssistant.Export.Runtime

  def publish_all_selects(publish_fun, config) when is_function(publish_fun, 3) do
    if Runtime.export_enabled?(config) and Runtime.area_selects_enabled?(config) do
      Entities.list_areas()
      |> Enum.each(fn area ->
        :ok = Publisher.publish_area_select_payloads(publish_fun, area, config)
      end)
    end

    :ok
  end

  def publish_select(publish_fun, area_id, config)
      when is_function(publish_fun, 3) and is_integer(area_id) do
    if Runtime.export_enabled?(config) and Runtime.area_selects_enabled?(config) do
      Publisher.publish_area_select_payloads(publish_fun, area_id, config)
    else
      :ok
    end
  end

  def unpublish_select(publish_fun, area_id, identifier, config)
      when is_function(publish_fun, 3) and is_integer(area_id) and is_binary(identifier) do
    if Runtime.export_enabled?(config) and Runtime.area_selects_enabled?(config) do
      Publisher.unpublish_area_select_payloads(publish_fun, area_id, identifier, config)
    else
      :ok
    end
  end

  def unpublish_all_selects(publish_fun, config) when is_function(publish_fun, 3) do
    Entities.list_areas()
    |> Enum.each(fn area ->
      :ok = Publisher.unpublish_area_select_payloads(publish_fun, area, config)
    end)

    :ok
  end
end
