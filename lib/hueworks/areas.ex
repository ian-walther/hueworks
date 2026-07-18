defmodule Hueworks.Areas do
  @moduledoc """
  Query helpers for areas.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Area, Scene}

  def list_areas do
    Repo.all(from(r in Area, order_by: [asc: r.name]))
  end

  def list_areas_with_children do
    Repo.all(from(r in Area, order_by: [asc: r.name]))
    |> Repo.preload([:groups, :lights, :scenes, :presence_inputs])
  end

  def get_area(id), do: Repo.get(Area, id)

  def create_area(attrs) do
    %Area{}
    |> Area.changeset(attrs)
    |> Repo.insert()
  end

  def update_area(area, attrs) do
    case area
         |> Area.changeset(attrs)
         |> Repo.update() do
      {:ok, updated} ->
        HomeAssistantExport.refresh_area(updated.id)
        {:ok, updated}

      other ->
        other
    end
  end

  def delete_area(area) do
    scene_ids =
      Repo.all(from(s in Scene, where: s.area_id == ^area.id, select: s.id))

    case Repo.delete(area) do
      {:ok, deleted} ->
        Enum.each(scene_ids, &HomeAssistantExport.remove_scene/1)
        HomeAssistantExport.remove_area(deleted)
        {:ok, deleted}

      other ->
        other
    end
  end
end
