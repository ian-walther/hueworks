defmodule Hueworks.Scenes.Active do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.Control.DesiredState
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{ActiveScene, Scene, SceneComponent, SceneComponentLight}

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
            Scenes.apply_active_scene(scene, active_scene, preserve_power_latches: true)

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
        preserve_power_latches: true
      )
      |> case do
        {:ok, _diff, _updated} -> [scene | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
    |> then(&{:ok, &1})
  end

  def rehydrate_needed?(scene_id) when is_integer(scene_id) do
    scene_id
    |> scene_light_ids()
    |> Enum.any?(fn light_id ->
      DesiredState.get(:light, light_id) == nil
    end)
  end

  def rehydrate_needed?(_scene_id), do: false

  def follow_presence_light_ids(scene_id, presence_input_id)
      when is_integer(scene_id) and is_integer(presence_input_id) do
    Repo.all(
      from(scl in SceneComponentLight,
        join: sc in SceneComponent,
        on: sc.id == scl.scene_component_id,
        where:
          sc.scene_id == ^scene_id and scl.default_power == :follow_presence and
            scl.presence_input_id == ^presence_input_id,
        select: scl.light_id
      )
    )
  end

  def follow_presence_light_ids(_scene_id, _presence_input_id), do: []

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
        with {:ok, active_scene, power_overrides} <-
               persist_power_overrides(active_scene, room_id, light_ids, opts) do
          active_scene.scene_id
          |> Scenes.get_scene()
          |> case do
            nil ->
              {:error, :not_found}

            scene ->
              Scenes.apply_active_scene(scene, active_scene,
                preserve_power_latches: true,
                target_light_ids: light_ids,
                circadian_only: Keyword.get(opts, :circadian_only, false),
                power_overrides: power_overrides,
                now: Keyword.get(opts, :now, DateTime.utc_now()),
                trace: Keyword.get(opts, :trace),
                origin: Keyword.get(opts, :origin, :manual),
                transition_policy: Keyword.get(opts, :transition_policy),
                group_candidate_light_ids: Keyword.get(opts, :group_candidate_light_ids)
              )
          end
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

  defp persist_power_overrides(active_scene, room_id, light_ids, opts) do
    opts
    |> Keyword.get(:power_override)
    |> case do
      nil ->
        {:ok, active_scene, %{}}

      power when power in [:on, :off] ->
        power_overrides = Map.new(light_ids, &{&1, power})

        persist_fun =
          Keyword.get(opts, :power_override_persist_fun, &ActiveScenes.merge_power_overrides/2)

        case persist_fun.(room_id, power_overrides) do
          {:ok, updated_active_scene} ->
            {:ok, updated_active_scene, power_overrides}

          {:error, _reason} = error ->
            error

          other ->
            {:error, {:invalid_power_override_persist_result, other}}
        end

      _power ->
        {:error, :invalid_power_override}
    end
  end

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

  defp scene_light_ids(scene_id) do
    Repo.all(
      from(scl in SceneComponentLight,
        join: sc in SceneComponent,
        on: sc.id == scl.scene_component_id,
        where: sc.scene_id == ^scene_id,
        select: scl.light_id
      )
    )
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
