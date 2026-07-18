defmodule Hueworks.Import.Areas do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.Normalize
  alias Hueworks.Repo
  alias Hueworks.Schemas.Area
  alias Hueworks.Util

  def upsert(area, plan) do
    case Normalize.fetch(plan, :action) || "create" do
      "skip" ->
        nil

      "merge" ->
        plan
        |> Normalize.fetch(:target_area_id)
        |> Util.parse_optional_integer()
        |> then(fn
          nil -> nil
          id -> if Repo.get(Area, id), do: id
        end)

      _ ->
        name = Normalize.fetch(area, :name) || "Area"
        normalized_name = Normalize.normalize_area_name(name)

        case Repo.one(from(r in Area, where: fragment("lower(?)", r.name) == ^normalized_name)) do
          nil ->
            %Area{}
            |> Area.changeset(%{
              name: name,
              metadata: %{"normalized_name" => normalized_name}
            })
            |> Repo.insert!()
            |> Map.fetch!(:id)

          area ->
            area.id
        end
    end
  end

  def target_id_for(entry, area_map, plan_map) do
    source_id =
      entry
      |> Normalize.fetch(:source_id)
      |> Normalize.normalize_source_id()

    plan_entry = if is_binary(source_id), do: Normalize.fetch(plan_map, source_id), else: nil

    case Normalize.fetch(plan_entry, :target_area_id) do
      "unassigned" ->
        nil

      target_area_id ->
        case Util.parse_optional_integer(target_area_id) do
          id when is_integer(id) -> id
          _ -> bridge_area_id(entry, area_map)
        end
    end
  end

  defp bridge_area_id(entry, area_map) do
    entry
    |> Normalize.fetch(:area_source_id)
    |> Normalize.normalize_source_id()
    |> then(&Map.get(area_map, &1))
  end
end
