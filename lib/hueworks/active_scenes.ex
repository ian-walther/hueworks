defmodule Hueworks.ActiveScenes do
  @moduledoc """
  Tracks the active scene per area for circadian/manual polling.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.{ActiveScene, Scene}

  def topic, do: "active_scenes"

  def list_active_scenes do
    Repo.all(from(a in ActiveScene, select: a))
  end

  def get_for_area(area_id) do
    Repo.one(from(a in ActiveScene, where: a.area_id == ^area_id))
  end

  def set_active(%Scene{} = scene, opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    circadian_resume_at = Keyword.get(opts, :circadian_resume_at)

    attrs = %{
      area_id: scene.area_id,
      scene_id: scene.id,
      last_applied_at: now,
      power_overrides: %{},
      circadian_resume_at: circadian_resume_at
    }

    changeset = ActiveScene.changeset(%ActiveScene{}, attrs)

    result =
      try do
        Repo.insert(changeset,
          on_conflict: [
            set: [
              scene_id: scene.id,
              last_applied_at: now,
              power_overrides: %{},
              circadian_resume_at: circadian_resume_at,
              updated_at: now
            ]
          ],
          conflict_target: :area_id
        )
      rescue
        Ecto.ConstraintError ->
          {:error,
           Ecto.Changeset.add_error(changeset, :base, "active scene references are invalid")}
      end

    case result do
      {:ok, active_scene} ->
        broadcast(scene.area_id, scene.id)
        {:ok, active_scene}

      {:error, _reason} = error ->
        error
    end
  end

  def clear_for_area(area_id) do
    Repo.delete_all(from(a in ActiveScene, where: a.area_id == ^area_id))
    broadcast(area_id, nil)
    :ok
  end

  def deactivate_scene(scene_id) when is_integer(scene_id) do
    area_ids =
      Repo.all(from(a in ActiveScene, where: a.scene_id == ^scene_id, select: a.area_id))

    Repo.delete_all(from(a in ActiveScene, where: a.scene_id == ^scene_id))

    Enum.each(area_ids, fn area_id ->
      broadcast(area_id, nil)
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

  def circadian_deferred?(%ActiveScene{circadian_resume_at: %DateTime{} = resume_at}, now)
      when is_struct(now, DateTime) do
    DateTime.compare(now, resume_at) == :lt
  end

  def circadian_deferred?(_active_scene, _now), do: false

  def remaining_circadian_deferral_ms(
        %ActiveScene{circadian_resume_at: %DateTime{} = resume_at},
        now
      )
      when is_struct(now, DateTime) do
    max(DateTime.diff(resume_at, now, :millisecond), 0)
  end

  def remaining_circadian_deferral_ms(_active_scene, _now), do: 0

  def power_overrides(%ActiveScene{} = active_scene) do
    active_scene.power_overrides
    |> normalize_power_overrides()
  end

  def power_overrides(_active_scene), do: %{}

  def merge_power_overrides(area_id, overrides)
      when is_integer(area_id) and is_map(overrides) do
    area_id
    |> get_for_area()
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

  def merge_power_overrides(_area_id, _overrides), do: {:error, :invalid_args}

  defp broadcast(area_id, scene_id) when is_integer(area_id) do
    Phoenix.PubSub.broadcast(
      Hueworks.PubSub,
      topic(),
      {:active_scene_updated, area_id, scene_id}
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
