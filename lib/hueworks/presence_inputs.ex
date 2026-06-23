defmodule Hueworks.PresenceInputs do
  @moduledoc """
  Room-scoped presence input helpers.

  Presence inputs are room-scoped booleans configured in HueWorks and driven by
  Home Assistant. When an input changes, the room's active scene is reapplied so
  scene components using Follow Presence can update their lights.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.PresenceInput

  def list_for_room(room_id) when is_integer(room_id) do
    Repo.all(
      from(pi in PresenceInput,
        where: pi.room_id == ^room_id,
        order_by: [asc: pi.name]
      )
    )
  end

  def get_input(id) when is_integer(id), do: Repo.get(PresenceInput, id)
  def get_input(id) when is_binary(id), do: id |> Hueworks.Util.parse_id() |> get_input()
  def get_input(_id), do: nil

  def create_input(room_id, attrs) when is_integer(room_id) and is_map(attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %PresenceInput{}
    |> PresenceInput.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, input} ->
        HomeAssistantExport.refresh_presence_input(input.id)
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
        HomeAssistantExport.refresh_presence_input(updated.id)
        {:ok, updated}

      other ->
        other
    end
  end

  def delete_input(%PresenceInput{} = input) do
    input_id = input.id

    case Repo.delete(input) do
      {:ok, deleted} ->
        HomeAssistantExport.remove_presence_input(input_id)
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
              refresh_room_active_scene(updated)
            end

            {:ok, updated}

          other ->
            other
        end
    end
  end

  defp refresh_room_active_scene(%PresenceInput{room_id: room_id, id: input_id}) do
    case Hueworks.ActiveScenes.get_for_room(room_id) do
      %{scene_id: scene_id} ->
        case Scenes.refresh_active_scene(scene_id) do
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
