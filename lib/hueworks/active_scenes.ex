defmodule Hueworks.ActiveScenes do
  @moduledoc """
  Tracks the active scene per room for circadian/manual polling.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Scene}

  def topic, do: "active_scenes"

  def list_active_scenes do
    Repo.all(from(a in ActiveScene, select: a))
  end

  def get_for_room(room_id) do
    Repo.one(from(a in ActiveScene, where: a.room_id == ^room_id))
  end

  def set_active(%Scene{} = scene) do
    now = DateTime.utc_now()

    attrs = %{
      room_id: scene.room_id,
      scene_id: scene.id,
      last_applied_at: now,
      power_overrides: %{}
    }

    result =
      %ActiveScene{}
      |> ActiveScene.changeset(attrs)
      |> Repo.insert(
        on_conflict: [
          set: [
            scene_id: scene.id,
            last_applied_at: now,
            power_overrides: %{},
            updated_at: now
          ]
        ],
        conflict_target: :room_id
      )

    case result do
      {:ok, active_scene} ->
        HomeAssistantExport.refresh_room_select(scene.room_id)
        broadcast(scene.room_id, scene.id)
        {:ok, active_scene}

      {:error, _reason} = error ->
        error
    end
  end

  def clear_for_room(room_id) do
    Repo.delete_all(from(a in ActiveScene, where: a.room_id == ^room_id))
    HomeAssistantExport.refresh_room_select(room_id)
    broadcast(room_id, nil)
    :ok
  end

  def deactivate_scene(scene_id) when is_integer(scene_id) do
    room_ids =
      Repo.all(from(a in ActiveScene, where: a.scene_id == ^scene_id, select: a.room_id))

    Repo.delete_all(from(a in ActiveScene, where: a.scene_id == ^scene_id))

    Enum.each(room_ids, fn room_id ->
      HomeAssistantExport.refresh_room_select(room_id)
      broadcast(room_id, nil)
    end)

    :ok
  end

  def mark_applied(%ActiveScene{id: id}) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(a in ActiveScene, where: a.id == ^id),
      set: [last_applied_at: now, updated_at: now]
    )

    :ok
  end

  def power_overrides(%ActiveScene{} = active_scene) do
    active_scene.power_overrides
    |> normalize_power_overrides()
  end

  def power_overrides(_active_scene), do: %{}

  def merge_power_overrides(room_id, overrides)
      when is_integer(room_id) and is_map(overrides) do
    room_id
    |> get_for_room()
    |> case do
      nil ->
        {:error, :not_found}

      %ActiveScene{} = active_scene ->
        merged_overrides =
          active_scene
          |> power_overrides()
          |> Map.merge(normalize_power_overrides(overrides))
          |> dump_power_overrides()

        active_scene
        |> ActiveScene.changeset(%{power_overrides: merged_overrides})
        |> Repo.update()
    end
  end

  def merge_power_overrides(_room_id, _overrides), do: {:error, :invalid_args}

  defp broadcast(room_id, scene_id) when is_integer(room_id) do
    Phoenix.PubSub.broadcast(
      Hueworks.PubSub,
      topic(),
      {:active_scene_updated, room_id, scene_id}
    )
  end

  defp normalize_power_overrides(overrides) when is_map(overrides) do
    overrides
    |> Enum.reduce(%{}, fn {light_id, power}, acc ->
      case {parse_light_id(light_id), normalize_power(power)} do
        {light_id, power} when is_integer(light_id) and power in [:on, :off] ->
          Map.put(acc, light_id, power)

        _ ->
          acc
      end
    end)
  end

  defp normalize_power_overrides(_overrides), do: %{}

  defp dump_power_overrides(overrides) when is_map(overrides) do
    overrides
    |> normalize_power_overrides()
    |> Enum.reduce(%{}, fn {light_id, power}, acc ->
      Map.put(acc, Integer.to_string(light_id), Atom.to_string(power))
    end)
  end

  defp parse_light_id(light_id) when is_integer(light_id), do: light_id

  defp parse_light_id(light_id) when is_binary(light_id) do
    case Integer.parse(light_id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_light_id(_light_id), do: nil

  defp normalize_power(power) when power in [:on, :off], do: power
  defp normalize_power("on"), do: :on
  defp normalize_power("off"), do: :off
  defp normalize_power(_power), do: nil
end
