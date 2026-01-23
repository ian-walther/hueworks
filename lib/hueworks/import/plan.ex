defmodule Hueworks.Import.Plan do
  @moduledoc false

  alias Hueworks.Import.Normalize

  def build_default(normalized) when is_map(normalized) do
    rooms = Normalize.fetch(normalized, :rooms) || []
    lights = Normalize.fetch(normalized, :lights) || []
    groups = Normalize.fetch(normalized, :groups) || []

    %{
      rooms: build_room_plan(rooms),
      lights: build_selection(lights),
      groups: build_selection(groups)
    }
  end

  defp build_room_plan(rooms) do
    Enum.reduce(rooms, %{}, fn room, acc ->
      source_id = Normalize.fetch(room, :source_id) |> normalize_source_id()

      if source_id do
        Map.put(acc, source_id, %{
          "action" => "create",
          "target_room_id" => nil,
          "name" => Normalize.fetch(room, :name)
        })
      else
        acc
      end
    end)
  end

  defp build_selection(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      source_id = Normalize.fetch(item, :source_id) |> normalize_source_id()

      if source_id do
        Map.put(acc, source_id, true)
      else
        acc
      end
    end)
  end

  defp normalize_source_id(id) when is_binary(id), do: id
  defp normalize_source_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_source_id(id) when is_float(id), do: Float.to_string(id)
  defp normalize_source_id(_id), do: nil
end
