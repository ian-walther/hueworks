defmodule Hueworks.Occupancy do
  @moduledoc """
  Room-scoped occupancy source helpers.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{OccupancySource, Room}

  @default_source_name "Room Occupancy"

  def default_source_name, do: @default_source_name

  def list_sources do
    Repo.all(
      from(os in OccupancySource,
        join: r in assoc(os, :room),
        preload: [room: r],
        order_by: [asc: r.name, asc: os.name]
      )
    )
  end

  def list_sources_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(os in OccupancySource,
        where: os.room_id == ^room_id,
        order_by: [asc: os.name]
      )
    )
  end

  def get_source(id) when is_integer(id) do
    OccupancySource
    |> Repo.get(id)
    |> Repo.preload(:room)
  end

  def create_source(room_id, attrs) when is_integer(room_id) and is_map(attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %OccupancySource{}
    |> OccupancySource.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, source} ->
        HomeAssistantExport.refresh_occupancy_source(source.id)
        {:ok, source}

      other ->
        other
    end
  end

  def update_source(%OccupancySource{} = source, attrs) when is_map(attrs) do
    source
    |> OccupancySource.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        HomeAssistantExport.refresh_occupancy_source(updated.id)
        {:ok, updated}

      other ->
        other
    end
  end

  def delete_source(%OccupancySource{} = source) do
    if default_source?(source) do
      {:error, :default_source}
    else
      source_id = source.id

      source
      |> Repo.delete()
      |> case do
        {:ok, deleted} ->
          HomeAssistantExport.remove_occupancy_source(source_id)
          {:ok, deleted}

        other ->
          other
      end
    end
  end

  def room_occupied?(room_id) when is_integer(room_id) do
    case default_source_for_room(room_id) do
      %OccupancySource{occupied: occupied} ->
        occupied

      nil ->
        case Repo.one(from(r in Room, where: r.id == ^room_id, select: r.occupied)) do
          nil -> true
          value -> value
        end
    end
  end

  def set_room_occupied(room_id, occupied)
      when is_integer(room_id) and is_boolean(occupied) do
    Repo.transaction(fn ->
      Repo.update_all(
        from(r in Room, where: r.id == ^room_id),
        set: [occupied: occupied]
      )

      upsert_default_source(room_id, occupied)
    end)
    |> case do
      {:ok, _source} ->
        HomeAssistantExport.refresh_occupancy_sources_for_room(room_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def set_source_occupied(source_id, occupied, opts \\ [])

  def set_source_occupied(source_id, occupied, opts)
      when is_integer(source_id) and is_boolean(occupied) do
    Repo.transaction(fn ->
      source =
        OccupancySource
        |> Repo.get!(source_id)
        |> OccupancySource.changeset(%{occupied: occupied})
        |> Repo.update!()

      if default_source?(source) do
        Repo.update_all(
          from(r in Room, where: r.id == ^source.room_id),
          set: [occupied: occupied]
        )
      end

      source
    end)
    |> case do
      {:ok, source} ->
        source = Repo.preload(source, :room)

        if Keyword.get(opts, :refresh_home_assistant, true) do
          HomeAssistantExport.refresh_occupancy_source(source.id)
        end

        if Keyword.get(opts, :reapply_active_scene, true) do
          reapply_active_scene(source.room_id)
        end

        {:ok, source}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def set_source_occupied(_source_id, _occupied, _opts), do: {:error, :invalid_args}

  def source_occupied_map_for_room(room_id) when is_integer(room_id) do
    room_id
    |> list_sources_for_room()
    |> Map.new(&{&1.id, &1.occupied})
  end

  def default_source_for_room(room_id) when is_integer(room_id) do
    Repo.one(
      from(os in OccupancySource,
        where: os.room_id == ^room_id and os.name == ^@default_source_name,
        limit: 1
      )
    )
  end

  defp upsert_default_source(room_id, occupied) do
    case default_source_for_room(room_id) do
      %OccupancySource{} = source ->
        source
        |> OccupancySource.changeset(%{occupied: occupied})
        |> Repo.update!()

      nil ->
        %OccupancySource{}
        |> OccupancySource.changeset(%{
          room_id: room_id,
          name: @default_source_name,
          occupied: occupied,
          metadata: %{}
        })
        |> Repo.insert!()
    end
  end

  defp default_source?(%OccupancySource{name: @default_source_name}), do: true
  defp default_source?(_source), do: false

  defp reapply_active_scene(room_id) do
    case ActiveScenes.get_for_room(room_id) do
      %{scene_id: scene_id} = active_scene ->
        case Scenes.get_scene(scene_id) do
          nil ->
            :ok

          scene ->
            _ =
              Scenes.apply_active_scene(scene, active_scene,
                preserve_power_latches: false,
                occupied: room_occupied?(room_id)
              )

            :ok
        end

      _ ->
        :ok
    end
  end
end
