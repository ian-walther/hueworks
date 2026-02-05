defmodule Hueworks.Scenes do
  @moduledoc """
  Query helpers for scenes.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Control.DesiredState
  alias Hueworks.Schemas.{LightState, Scene, SceneComponent, SceneComponentLight}

  def list_scenes_for_room(room_id) do
    Repo.all(from(s in Scene, where: s.room_id == ^room_id, order_by: [asc: s.name]))
  end

  def list_manual_light_states do
    Repo.all(
      from(ls in LightState,
        where: ls.type == :manual,
        order_by: [asc: ls.name, asc: ls.id]
      )
    )
  end

  def create_manual_light_state(name, config \\ %{}) do
    %LightState{}
    |> LightState.changeset(%{
      name: name,
      type: :manual,
      config: config || %{}
    })
    |> Repo.insert()
  end

  def update_manual_light_state(id, attrs) do
    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: :manual} = state ->
        config = Map.merge(state.config || %{}, Map.get(attrs, :config, %{}))
        merged_attrs = Map.merge(%{name: state.name, type: state.type, config: config}, attrs)

        state
        |> LightState.changeset(merged_attrs)
        |> Repo.update()

      _ ->
        {:error, :invalid_type}
    end
  end

  def duplicate_manual_light_state(id) do
    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: :manual} = state ->
        %LightState{}
        |> LightState.changeset(%{
          name: "#{state.name} Copy",
          type: :manual,
          config: Map.new(state.config || %{})
        })
        |> Repo.insert()

      _ ->
        {:error, :invalid_type}
    end
  end

  def delete_manual_light_state(id, opts \\ []) do
    scene_id = Keyword.get(opts, :scene_id)

    case Repo.get(LightState, id) do
      nil ->
        {:error, :not_found}

      %LightState{type: :manual} = state ->
        in_use =
          Repo.aggregate(
            from(sc in SceneComponent, where: sc.light_state_id == ^state.id),
            :count
          )

        cond do
          in_use == 0 ->
            Repo.delete(state)

          is_integer(scene_id) ->
            current_scene_count =
              Repo.aggregate(
                from(sc in SceneComponent,
                  where: sc.light_state_id == ^state.id and sc.scene_id == ^scene_id
                ),
                :count
              )

            if current_scene_count == in_use do
              off = get_or_create_off_state()

              _ =
                Repo.update_all(
                  from(sc in SceneComponent,
                    where: sc.light_state_id == ^state.id and sc.scene_id == ^scene_id
                  ),
                  set: [light_state_id: off.id]
                )

              Repo.delete(state)
            else
              {:error, :in_use}
            end

          true ->
            {:error, :in_use}
        end

      _ ->
        {:error, :invalid_type}
    end
  end

  def get_or_create_off_state do
    case Repo.one(from(ls in LightState, where: ls.type == :off, limit: 1)) do
      nil ->
        %LightState{}
        |> LightState.changeset(%{
          name: "Off",
          type: :off,
          config: %{}
        })
        |> Repo.insert!()

      state ->
        state
    end
  end

  def create_scene(attrs) do
    %Scene{}
    |> Scene.changeset(attrs)
    |> Repo.insert()
  end

  def get_scene(id), do: Repo.get(Scene, id)

  def update_scene(scene, attrs) do
    scene
    |> Scene.changeset(attrs)
    |> Repo.update()
  end

  def delete_scene(scene) do
    Repo.delete(scene)
  end

  def activate_scene(scene_id) when is_integer(scene_id) do
    case Repo.get(Scene, scene_id) do
      nil ->
        {:error, :not_found}

      scene ->
        scene =
          scene
          |> Repo.preload(scene_components: [:lights, :light_state])

        txn = DesiredState.begin(scene.id)

        txn =
          Enum.reduce(scene.scene_components, txn, fn component, txn ->
            desired = desired_from_light_state(component.light_state)

            Enum.reduce(component.lights, txn, fn light, txn ->
              DesiredState.apply(txn, :light, light.id, desired)
            end)
          end)

        result = DesiredState.commit(txn)

        case result do
          {:ok, diff, _updated} ->
            plan = Hueworks.Control.Planner.plan_room(scene.room_id, diff)
            _ = Hueworks.Control.Executor.enqueue(plan)
            result

          _ ->
            result
        end
    end
  end

  defp desired_from_light_state(%LightState{type: :off}), do: %{power: :off}

  defp desired_from_light_state(%LightState{type: :manual, config: config}) do
    base = %{power: :on}

    base
    |> maybe_put(:brightness, config, ["brightness"])
    |> maybe_put(:kelvin, config, ["temperature", "kelvin"])
  end

  defp desired_from_light_state(_), do: %{}

  defp maybe_put(attrs, key, config, keys) do
    value =
      Enum.find_value(keys, fn config_key ->
        Map.get(config, config_key) ||
          Map.get(config, map_key_atom(config_key))
      end)

    if is_nil(value) do
      attrs
    else
      Map.put(attrs, key, value)
    end
  end

  defp map_key_atom("brightness"), do: :brightness
  defp map_key_atom("temperature"), do: :temperature
  defp map_key_atom("kelvin"), do: :kelvin
  defp map_key_atom(_), do: nil

  def replace_scene_components(%Scene{} = scene, components) when is_list(components) do
    Repo.transaction(fn ->
      old_light_state_ids =
        Repo.all(
          from(sc in SceneComponent,
            where: sc.scene_id == ^scene.id,
            select: sc.light_state_id
          )
        )

      Repo.delete_all(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

      Enum.each(components, fn component ->
        light_state = resolve_component_light_state(component)

        scene_component =
          %SceneComponent{}
          |> SceneComponent.changeset(%{
            name: Map.get(component, :name),
            scene_id: scene.id,
            light_state_id: light_state.id,
            metadata: %{}
          })
          |> Repo.insert!()

        light_ids = Map.get(component, :light_ids, [])

        Enum.each(light_ids, fn light_id ->
          %SceneComponentLight{}
          |> SceneComponentLight.changeset(%{
            scene_component_id: scene_component.id,
            light_id: light_id
          })
          |> Repo.insert()
        end)
      end)

      cleanup_light_states(old_light_state_ids)
    end)
  end

  defp cleanup_light_states(light_state_ids) do
    light_state_ids
    |> Enum.uniq()
    |> Enum.each(fn light_state_id ->
      count =
        Repo.aggregate(
          from(sc in SceneComponent, where: sc.light_state_id == ^light_state_id),
          :count
        )

      if count == 0 and off_light_state?(light_state_id) do
        Repo.delete_all(from(ls in LightState, where: ls.id == ^light_state_id))
      end
    end)
  end

  defp resolve_component_light_state(component) do
    state_id = Map.get(component, :light_state_id)

    cond do
      state_id in [nil, "off", :off] ->
        get_or_create_off_state()

      true ->
        state_id
        |> parse_id()
        |> case do
          nil -> get_or_create_off_state()
          id -> Repo.get(LightState, id) || get_or_create_off_state()
        end
    end
  end

  defp off_light_state?(light_state_id) do
    case Repo.get(LightState, light_state_id) do
      %LightState{type: :off} -> true
      _ -> false
    end
  end

defp parse_id(value), do: Hueworks.Util.parse_id(value)
end
