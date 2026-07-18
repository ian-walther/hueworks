defmodule Hueworks.PresenceInputs do
  @moduledoc """
  Area-scoped presence input helpers.

  Presence inputs are area-scoped booleans configured in HueWorks and driven by
  Home Assistant. When an input changes, only active-scene lights that use
  Follow Presence with that input are recomputed.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Hueworks.DomainEvents
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Schemas.PresenceInput

  def list_for_area(area_id) when is_integer(area_id) do
    Repo.all(
      from(pi in PresenceInput,
        where: pi.area_id == ^area_id,
        order_by: [asc: pi.name]
      )
    )
  end

  def get_input(id) when is_integer(id), do: Repo.get(PresenceInput, id)
  def get_input(id) when is_binary(id), do: id |> Hueworks.Util.parse_id() |> get_input()
  def get_input(_id), do: nil

  def create_input(area_id, attrs) when is_integer(area_id) and is_map(attrs) do
    attrs = Map.put(attrs, :area_id, area_id)

    %PresenceInput{}
    |> PresenceInput.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, input} ->
        DomainEvents.presence_input_changed(input)
        {:ok, input}

      other ->
        other
    end
  end

  def update_input(%PresenceInput{} = input, attrs) when is_map(attrs) do
    input
    |> PresenceInput.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        DomainEvents.presence_input_changed(updated)
        {:ok, updated}

      other ->
        other
    end
  end

  def delete_input(%PresenceInput{} = input) do
    input_id = input.id

    case Repo.delete(input) do
      {:ok, deleted} ->
        DomainEvents.presence_input_deleted(input_id)
        {:ok, deleted}

      other ->
        other
    end
  end

  def set_occupied(input_id, occupied, opts \\ [])
      when is_integer(input_id) and is_boolean(occupied) do
    refresh_home_assistant? = Keyword.get(opts, :refresh_home_assistant, true)
    refresh_active_scene? = Keyword.get(opts, :refresh_active_scene, true)

    case Repo.get(PresenceInput, input_id) do
      nil ->
        {:error, :not_found}

      %PresenceInput{} = input ->
        input
        |> PresenceInput.changeset(%{occupied: occupied})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            if refresh_home_assistant? do
              HomeAssistantExport.refresh_presence_input(updated.id)
            end

            if refresh_active_scene? do
              refresh_area_active_scene(updated)
            end

            {:ok, updated}

          other ->
            other
        end
    end
  end

  defp refresh_area_active_scene(%PresenceInput{area_id: area_id, id: input_id}) do
    case Hueworks.ActiveScenes.get_for_area(area_id) do
      %{scene_id: scene_id} ->
        light_ids = Scenes.active_scene_follow_presence_light_ids(scene_id, input_id)

        case Scenes.recompute_active_scene_lights(area_id, light_ids,
               origin: :presence,
               group_candidate_light_ids: light_ids
             ) do
          {:ok, _diff, _updated} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Presence input #{input_id} changed, but active scene #{scene_id} refresh failed: #{inspect(reason)}"
            )
        end

      _ ->
        :ok
    end
  end
end
