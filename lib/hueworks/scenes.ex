defmodule Hueworks.Scenes do
  @moduledoc """
  Query helpers for scenes.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Scenes.Active
  alias Hueworks.Scenes.Apply, as: SceneApply
  alias Hueworks.Scenes.Components
  alias Hueworks.Scenes.LightStates
  alias Hueworks.Scenes.Persistence
  alias Hueworks.ActiveScenes
  alias Hueworks.Repo
  alias Hueworks.Schemas.Scene

  @type scene_apply_result :: {:ok, map(), map()} | {:error, term()}
  @type scene_result :: {:ok, struct()} | {:error, term()}
  @type light_state_type :: :manual | :circadian

  @spec list_scenes_for_area(integer()) :: list(struct())
  def list_scenes_for_area(area_id) do
    Repo.all(from(s in Scene, where: s.area_id == ^area_id, order_by: [asc: s.name]))
  end

  @spec list_manual_light_states() :: list(struct())
  def list_manual_light_states do
    LightStates.list_manual()
  end

  @spec list_editable_light_states() :: list(struct())
  def list_editable_light_states do
    LightStates.list_editable()
  end

  @spec list_editable_light_states_with_usage() :: list(map())
  def list_editable_light_states_with_usage do
    LightStates.list_editable_with_usage()
  end

  @spec get_editable_light_state(integer() | term()) :: struct() | nil
  def get_editable_light_state(id) when is_integer(id) do
    LightStates.get_editable(id)
  end

  def get_editable_light_state(_id), do: nil

  @spec light_state_usages(integer() | term()) :: list(map())
  def light_state_usages(id) when is_integer(id) do
    LightStates.usages(id)
  end

  def light_state_usages(_id), do: []

  @spec create_light_state(String.t(), light_state_type(), map()) ::
          {:ok, struct()} | {:error, term()}
  def create_light_state(name, type, config \\ %{})

  def create_light_state(name, type, config)
      when type in [:manual, :circadian] do
    LightStates.create(name, type, config)
  end

  def create_light_state(_name, _type, _config), do: {:error, :invalid_type}

  @spec update_light_state(integer(), map()) :: {:ok, struct()} | {:error, term()}
  def update_light_state(id, attrs) when is_integer(id) and is_map(attrs) do
    LightStates.update(id, attrs)
  end

  @spec duplicate_light_state(integer()) :: {:ok, struct()} | {:error, term()}
  def duplicate_light_state(id) when is_integer(id) do
    LightStates.duplicate(id)
  end

  @spec delete_light_state(integer()) :: :ok | {:error, term()}
  def delete_light_state(id) do
    LightStates.delete(id)
  end

  def create_manual_light_state(name, config \\ %{}),
    do: create_light_state(name, :manual, config)

  def create_scene(attrs) do
    Persistence.create(attrs)
  end

  @spec get_scene(term()) :: struct() | nil
  def get_scene(id), do: Repo.get(Scene, id)

  @spec update_scene(struct(), map()) :: scene_result()
  def update_scene(scene, attrs) do
    Persistence.update(scene, attrs)
  end

  @spec delete_scene(struct()) :: scene_result()
  def delete_scene(scene) do
    Persistence.delete(scene)
  end

  @spec refresh_active_scene(integer()) :: scene_apply_result()
  def refresh_active_scene(scene_id) when is_integer(scene_id) do
    Active.refresh_scene(scene_id)
  end

  def active_scene_rehydrate_needed?(scene_id) when is_integer(scene_id) do
    Active.rehydrate_needed?(scene_id)
  end

  def active_scene_rehydrate_needed?(_scene_id), do: false

  def active_scene_follow_presence_light_ids(scene_id, presence_input_id)
      when is_integer(scene_id) and is_integer(presence_input_id) do
    Active.follow_presence_light_ids(scene_id, presence_input_id)
  end

  def active_scene_follow_presence_light_ids(_scene_id, _presence_input_id), do: []

  @spec refresh_active_scenes_for_light_state(integer()) :: {:ok, list(struct())}
  def refresh_active_scenes_for_light_state(light_state_id) when is_integer(light_state_id) do
    Active.refresh_for_light_state(light_state_id)
  end

  @spec activate_scene(integer(), keyword()) :: scene_apply_result()
  def activate_scene(scene_id, opts \\ []) when is_integer(scene_id) do
    SceneApply.activate_scene(scene_id, opts)
  end

  def toggle_activation(scene_id, trace_source) when is_integer(scene_id) do
    case get_scene(scene_id) do
      nil ->
        {:error, :not_found}

      %Scene{} = scene ->
        case ActiveScenes.get_for_area(scene.area_id) do
          %{scene_id: ^scene_id} ->
            :ok = ActiveScenes.clear_for_area(scene.area_id)
            {:ok, :deactivated, scene}

          current_active ->
            trace = activation_trace(scene, current_active, trace_source)

            case activate_scene(scene_id, trace: trace) do
              {:ok, diff, updated} -> {:ok, :activated, scene, diff, updated}
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  def toggle_activation(_scene_id, _trace_source), do: {:error, :invalid_args}

  @spec apply_scene(struct(), keyword()) :: scene_apply_result()
  def apply_scene(%Scene{} = scene, opts \\ []) do
    SceneApply.apply_scene(scene, opts)
  end

  @spec apply_active_scene(struct(), map(), keyword()) :: scene_apply_result()
  def apply_active_scene(%Scene{} = scene, active_scene, opts \\ []) when is_list(opts) do
    SceneApply.apply_active_scene(scene, active_scene, opts)
  end

  @spec recompute_active_scene_lights(integer(), list(integer()), keyword()) ::
          scene_apply_result()
  def recompute_active_scene_lights(area_id, light_ids, opts \\ [])

  def recompute_active_scene_lights(area_id, light_ids, opts)
      when is_integer(area_id) and is_list(light_ids) do
    Active.recompute_lights(area_id, light_ids, opts)
  end

  def recompute_active_scene_lights(_area_id, _light_ids, _opts), do: {:error, :invalid_args}

  @spec recompute_active_circadian_lights(integer(), list(integer()), keyword()) ::
          scene_apply_result()
  def recompute_active_circadian_lights(area_id, light_ids, opts \\ [])

  def recompute_active_circadian_lights(area_id, light_ids, opts)
      when is_integer(area_id) and is_list(light_ids) do
    Active.recompute_circadian_lights(area_id, light_ids, opts)
  end

  def recompute_active_circadian_lights(_area_id, _light_ids, _opts),
    do: {:error, :invalid_args}

  @spec replace_scene_components(struct(), list(map())) :: :ok | {:error, term()}
  def replace_scene_components(%Scene{} = scene, components) when is_list(components) do
    Components.replace(scene, components)
  end

  defp activation_trace(scene, current_active, source) do
    %{
      trace_id: "scene-toggle-#{scene.area_id}-#{System.unique_integer([:positive])}",
      source: to_string(source),
      area_id: scene.area_id,
      previous_scene_id: Map.get(current_active || %{}, :scene_id),
      scene_id: scene.id,
      started_at_ms: System.monotonic_time(:millisecond)
    }
  end
end
