defmodule HueworksWeb.LightsLive.Filters do
  @moduledoc false

  alias Hueworks.Util

  def filter_entities(entities, filter, room_filter, show_disabled) do
    entities
    |> filter_by_source(filter)
    |> filter_by_room(room_filter)
    |> filter_by_enabled(show_disabled)
  end

  def filter_lights(entities, filter, room_filter, show_disabled, show_linked) do
    entities
    |> filter_entities(filter, room_filter, show_disabled)
    |> filter_by_linked(show_linked)
  end

  defp filter_by_source(entities, "all"), do: entities

  defp filter_by_source(entities, filter) when is_binary(filter) do
    case Util.parse_source_filter(filter) do
      {:ok, source} -> Enum.filter(entities, &(&1.source == source))
      :error -> entities
    end
  end

  defp filter_by_source(entities, _filter), do: entities

  defp filter_by_enabled(entities, true), do: entities

  defp filter_by_enabled(entities, _show_disabled) do
    Enum.filter(entities, &(&1.enabled != false))
  end

  defp filter_by_linked(entities, true), do: entities

  defp filter_by_linked(entities, _show_linked) do
    Enum.filter(entities, &is_nil(&1.canonical_light_id))
  end

  defp filter_by_room(entities, "all"), do: entities
  defp filter_by_room(entities, "unassigned"), do: Enum.filter(entities, &is_nil(&1.room_id))
  defp filter_by_room(entities, nil), do: entities
  defp filter_by_room(entities, room_id) when is_integer(room_id), do: Enum.filter(entities, &(&1.room_id == room_id))
  defp filter_by_room(entities, _room_id), do: entities
end
