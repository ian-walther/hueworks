defmodule Hueworks.Scenes.Active do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{ActiveScene, Scene, SceneComponent}

  def refresh_scene(scene_id) when is_integer(scene_id) do
    scene_id
    |> then(&Repo.get(Scene, &1))
    |> case do
      nil ->
        {:error, :not_found}

      %Scene{} = scene ->
        scene.room_id
        |> ActiveScenes.get_for_room()
        |> case do
          %{scene_id: ^scene_id} = active_scene ->
            Scenes.apply_active_scene(scene, active_scene,
              preserve_power_latches: true,
              occupied: Rooms.room_occupied?(scene.room_id)
            )

          _ ->
            {:ok, %{}, %{}}
        end
    end
  end

  def refresh_for_light_state(light_state_id) when is_integer(light_state_id) do
    light_state_id
    |> active_scene_pairs_for_light_state()
    |> Enum.reduce([], fn {scene, active_scene}, acc ->
      scene
      |> Scenes.apply_active_scene(active_scene,
        preserve_power_latches: true,
        occupied: Rooms.room_occupied?(scene.room_id)
      )
      |> case do
        {:ok, _diff, _updated} -> [scene | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
    |> then(&{:ok, &1})
  end

  def recompute_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    light_ids =
      light_ids
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    case {light_ids, ActiveScenes.get_for_room(room_id)} do
      {[], _active_scene} ->
        {:ok, %{}, %{}}

      {_light_ids, nil} ->
        {:ok, %{}, %{}}

      {_light_ids, active_scene} ->
        active_scene.scene_id
        |> Scenes.get_scene()
        |> case do
          nil ->
            {:error, :not_found}

          scene ->
            power_overrides =
              opts
              |> Keyword.get(:power_override)
              |> case do
                nil -> %{}
                power -> Map.new(light_ids, &{&1, power})
              end

            Scenes.apply_active_scene(scene, active_scene,
              preserve_power_latches: true,
              occupied: Rooms.room_occupied?(room_id),
              target_light_ids: light_ids,
              circadian_only: Keyword.get(opts, :circadian_only, false),
              power_overrides: power_overrides,
              now: Keyword.get(opts, :now, DateTime.utc_now()),
              trace: Keyword.get(opts, :trace)
            )
        end
    end
  end

  def recompute_lights(_room_id, _light_ids, _opts), do: {:error, :invalid_args}

  def recompute_circadian_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    opts
    |> Keyword.put(:circadian_only, true)
    |> then(&recompute_lights(room_id, light_ids, &1))
  end

  def recompute_circadian_lights(_room_id, _light_ids, _opts), do: {:error, :invalid_args}

  defp active_scene_pairs_for_light_state(light_state_id) do
    light_state_id
    |> scene_ids_for_light_state()
    |> then(fn scene_ids ->
      Repo.all(
        from(s in Scene,
          join: a in ActiveScene,
          on: a.scene_id == s.id and a.room_id == s.room_id,
          where: s.id in ^scene_ids,
          select: {s, a}
        )
      )
    end)
  end

  defp scene_ids_for_light_state(light_state_id) do
    Repo.all(
      from(sc in SceneComponent,
        where: sc.light_state_id == ^light_state_id,
        distinct: true,
        select: sc.scene_id
      )
    )
  end
end
