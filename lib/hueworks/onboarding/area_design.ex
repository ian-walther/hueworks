defmodule Hueworks.Onboarding.AreaDesign do
  @moduledoc """
  Builds and applies the reviewed HueWorks Area design from Home Assistant inventory.

  These operations only create Areas and manage ExternalSpaceMappings. Existing entity placement
  remains authored HueWorks configuration and is never changed here.
  """

  alias Hueworks.{Areas, Bridges, ExternalSpaces, Repo}
  alias Hueworks.Import.Normalize
  alias Hueworks.Schemas.{Area, Bridge, BridgeImport, ExternalSpace}

  def refresh(%Bridge{type: :ha} = bridge) do
    with %BridgeImport{} = bridge_import <- Bridges.latest_import(bridge),
         spaces <- Normalize.external_spaces(bridge_import.normalized_blob || %{}),
         {:ok, _persisted} <- ExternalSpaces.sync_bridge_spaces(bridge, spaces) do
      {:ok, design(bridge)}
    else
      nil -> {:error, :inventory_not_fetched}
      {:error, reason} -> {:error, reason}
    end
  end

  def design(%Bridge{type: :ha} = bridge) do
    spaces = ExternalSpaces.list_for_bridge(bridge)
    counts = entity_counts(Bridges.latest_import(bridge))

    floors = Enum.filter(spaces, &(&1.kind == "ha_floor"))
    areas = Enum.filter(spaces, &(&1.kind == "ha_area"))

    floor_entries =
      Enum.map(floors, fn floor ->
        children =
          areas
          |> Enum.filter(&(&1.parent_external_space_id == floor.id))
          |> Enum.map(&space_entry(&1, counts))

        %{
          space: floor,
          children: children,
          entity_count: Enum.sum(Enum.map(children, & &1.entity_count))
        }
      end)

    parent_ids = MapSet.new(floors, & &1.id)

    unfloored_areas =
      areas
      |> Enum.reject(&MapSet.member?(parent_ids, &1.parent_external_space_id))
      |> Enum.map(&space_entry(&1, counts))

    %{
      floors: floor_entries,
      unfloored_areas: unfloored_areas,
      areas: Areas.list_areas()
    }
  end

  def use_floor_as_one_area(%Bridge{type: :ha} = bridge, floor_external_id, attrs)
      when is_binary(floor_external_id) and is_map(attrs) do
    Repo.transaction(fn ->
      floor = require_space!(bridge, "ha_floor", floor_external_id)
      area = mapped_area(floor) || destination_area!(attrs)

      [floor | child_spaces(bridge, floor)]
      |> Enum.each(&put_mapping!(&1, area.id))

      area
    end)
  end

  def use_floor_areas_separately(%Bridge{type: :ha} = bridge, floor_external_id)
      when is_binary(floor_external_id) do
    Repo.transaction(fn ->
      floor = require_space!(bridge, "ha_floor", floor_external_id)
      :ok = ExternalSpaces.remove_mapping(floor)

      bridge
      |> child_spaces(floor)
      |> Enum.map(fn child ->
        area = mapped_area(child) || create_area!(%{name: child.name})
        put_mapping!(child, area.id)
        area
      end)
    end)
  end

  def map_space(%Bridge{} = bridge, kind, external_id, area_id)
      when is_binary(kind) and is_binary(external_id) and is_integer(area_id) do
    with %ExternalSpace{} = space <- ExternalSpaces.get_by_identity(bridge, kind, external_id),
         %Area{} <- Areas.get_area(area_id) do
      ExternalSpaces.put_mapping(space, area_id)
    else
      nil -> {:error, :not_found}
    end
  end

  def create_and_map_space(%Bridge{} = bridge, kind, external_id, attrs)
      when is_binary(kind) and is_binary(external_id) and is_map(attrs) do
    Repo.transaction(fn ->
      space = require_space!(bridge, kind, external_id)
      area = mapped_area(space) || create_area!(attrs)
      put_mapping!(space, area.id)
      area
    end)
  end

  def skip_floor(%Bridge{type: :ha} = bridge, floor_external_id)
      when is_binary(floor_external_id) do
    Repo.transaction(fn ->
      floor = require_space!(bridge, "ha_floor", floor_external_id)

      [floor | child_spaces(bridge, floor)]
      |> Enum.each(&remove_mapping!/1)

      :ok
    end)
    |> unwrap_ok()
  end

  def skip_space(%Bridge{} = bridge, kind, external_id)
      when is_binary(kind) and is_binary(external_id) do
    case ExternalSpaces.get_by_identity(bridge, kind, external_id) do
      %ExternalSpace{} = space -> ExternalSpaces.remove_mapping(space)
      nil -> {:error, :not_found}
    end
  end

  defp destination_area!(%{area_id: area_id}) when is_integer(area_id) do
    Areas.get_area(area_id) || Repo.rollback(:area_not_found)
  end

  defp destination_area!(attrs), do: create_area!(attrs)

  defp mapped_area(%ExternalSpace{} = space) do
    case ExternalSpaces.mapped_area_id(space.bridge_id, space.kind, space.external_id) do
      area_id when is_integer(area_id) -> Areas.get_area(area_id)
      nil -> nil
    end
  end

  defp create_area!(attrs) do
    case Areas.create_area(attrs) do
      {:ok, area} -> area
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp require_space!(bridge, kind, external_id) do
    ExternalSpaces.get_by_identity(bridge, kind, external_id) || Repo.rollback(:space_not_found)
  end

  defp child_spaces(bridge, %ExternalSpace{id: parent_id}) do
    bridge
    |> ExternalSpaces.list_for_bridge()
    |> Enum.filter(&(&1.kind == "ha_area" and &1.parent_external_space_id == parent_id))
  end

  defp put_mapping!(space, area_id) do
    case ExternalSpaces.put_mapping(space, area_id) do
      {:ok, mapping} -> mapping
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp remove_mapping!(space) do
    case ExternalSpaces.remove_mapping(space) do
      :ok -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp entity_counts(%BridgeImport{} = bridge_import) do
    normalized = bridge_import.normalized_blob || %{}

    ((Normalize.fetch(normalized, :lights) || []) ++
       (Normalize.fetch(normalized, :groups) || []))
    |> Enum.reduce(%{}, fn entity, counts ->
      entity
      |> Normalize.entity_space_refs()
      |> Enum.reduce(counts, fn ref, acc ->
        key = {
          Normalize.fetch(ref, :kind) |> Normalize.normalize_space_kind(),
          Normalize.fetch(ref, :external_id) |> Normalize.normalize_source_id()
        }

        Map.update(acc, key, 1, &(&1 + 1))
      end)
    end)
  end

  defp entity_counts(_bridge_import), do: %{}

  defp space_entry(space, counts) do
    %{
      space: space,
      entity_count: Map.get(counts, {space.kind, space.external_id}, 0)
    }
  end

  defp unwrap_ok({:ok, :ok}), do: :ok
  defp unwrap_ok(other), do: other
end
