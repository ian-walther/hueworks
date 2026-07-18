defmodule Hueworks.Import.Plan do
  @moduledoc false

  alias Hueworks.Import.{Normalize, SpaceMappings}

  def build_default(normalized) when is_map(normalized) do
    areas = Normalize.fetch(normalized, :areas) || []
    lights = Normalize.fetch(normalized, :lights) || []
    groups = Normalize.fetch(normalized, :groups) || []

    %{
      areas: build_area_plan(areas),
      external_space_mappings: build_external_space_plan(Normalize.external_spaces(normalized)),
      lights: build_selection(lights),
      groups: build_selection(groups)
    }
  end

  defp build_external_space_plan(spaces) do
    Enum.reduce(spaces, %{}, fn space, acc ->
      case SpaceMappings.identity(space) do
        {kind, external_id} = identity when is_binary(kind) and is_binary(external_id) ->
          Map.put(acc, SpaceMappings.key(identity), %{
            "kind" => kind,
            "external_id" => external_id,
            "action" => "skip",
            "target_area_id" => nil
          })

        _ ->
          acc
      end
    end)
  end

  defp build_area_plan(areas) do
    Enum.reduce(areas, %{}, fn area, acc ->
      source_id = Normalize.fetch(area, :source_id) |> Normalize.normalize_source_id()

      if source_id do
        Map.put(acc, source_id, %{
          "action" => "create",
          "target_area_id" => nil,
          "name" => Normalize.fetch(area, :name)
        })
      else
        acc
      end
    end)
  end

  defp build_selection(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      source_id = Normalize.fetch(item, :source_id) |> Normalize.normalize_source_id()

      if source_id do
        Map.put(acc, source_id, true)
      else
        acc
      end
    end)
  end
end
