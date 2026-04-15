defmodule Hueworks.Scenes.Components do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Scenes.Intent
  alias Hueworks.Schemas.{Light, LightState, Scene, SceneComponent, SceneComponentLight}

  def replace(%Scene{} = scene, components) when is_list(components) do
    Repo.transaction(fn ->
      Repo.delete_all(from(sc in SceneComponent, where: sc.scene_id == ^scene.id))

      components
      |> Enum.reduce_while(:ok, fn component, _acc ->
        component
        |> resolve_component_light_state()
        |> case do
          {:error, reason} ->
            Repo.rollback(reason)

          {:ok, light_state} ->
            component
            |> validate_component_targets(light_state)
            |> case do
              :ok ->
                component
                |> insert_scene_component(scene, light_state)
                |> insert_scene_component_lights(component)

                {:cont, :ok}

              {:error, reason} ->
                Repo.rollback(reason)
            end
        end
      end)
    end)
  end

  defp insert_scene_component(component, scene, light_state) do
    %SceneComponent{}
    |> SceneComponent.changeset(%{
      name: Map.get(component, :name),
      scene_id: scene.id,
      light_state_id: light_state.id,
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp insert_scene_component_lights(scene_component, component) do
    component
    |> Map.get(:light_ids, [])
    |> Enum.each(fn light_id ->
      %SceneComponentLight{}
      |> SceneComponentLight.changeset(%{
        scene_component_id: scene_component.id,
        light_id: light_id,
        default_power: Intent.default_power_for_light(component, light_id)
      })
      |> Repo.insert!()
    end)

    scene_component
  end

  defp resolve_component_light_state(component) do
    component
    |> Map.get(:light_state_id)
    |> case do
      state_id when state_id in [nil, "new", "new_manual", "new_circadian"] ->
        {:error, :invalid_light_state}

      state_id ->
        state_id
        |> Hueworks.Util.parse_id()
        |> case do
          nil ->
            {:error, :invalid_light_state}

          id ->
            case Repo.get(LightState, id) do
              %LightState{type: type} = state when type in [:manual, :circadian] ->
                {:ok, state}

              _ ->
                {:error, :invalid_light_state}
            end
        end
    end
  end

  defp validate_component_targets(component, %LightState{type: :manual, config: config}) do
    if manual_color_mode?(config) and component_has_non_color_lights?(component) do
      {:error, :invalid_color_targets}
    else
      :ok
    end
  end

  defp validate_component_targets(_component, _light_state), do: :ok

  defp component_has_non_color_lights?(component) do
    component
    |> Map.get(:light_ids, [])
    |> then(fn light_ids ->
      Repo.exists?(
        from(l in Light,
          where: l.id in ^light_ids and l.supports_color != true
        )
      )
    end)
  end

  defp manual_color_mode?(config) when is_map(config) do
    config
    |> LightState.manual_mode()
    |> Kernel.==(:color)
  end

  defp manual_color_mode?(_config), do: false
end
