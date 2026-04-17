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
  alias Hueworks.Repo
  alias Hueworks.Schemas.Scene

  @type scene_apply_result :: {:ok, map(), map()} | {:error, term()}
  @type scene_result :: {:ok, struct()} | {:error, term()}
  @type light_state_type :: :manual | :circadian

  @spec list_scenes_for_room(integer()) :: list(struct())
  def list_scenes_for_room(room_id) do
    Repo.all(from(s in Scene, where: s.room_id == ^room_id, order_by: [asc: s.name]))
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

  @spec delete_light_state(integer(), keyword()) :: :ok | {:error, term()}
  def delete_light_state(id, opts \\ []) do
    _scene_id = Keyword.get(opts, :scene_id)

    LightStates.delete(id)
  end

  def create_manual_light_state(name, config \\ %{}),
    do: create_light_state(name, :manual, config)

  def update_manual_light_state(id, attrs), do: update_light_state(id, attrs)
  def duplicate_manual_light_state(id), do: duplicate_light_state(id)
  def delete_manual_light_state(id, opts \\ []), do: delete_light_state(id, opts)

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

  @spec refresh_active_scenes_for_light_state(integer()) :: {:ok, list(struct())}
  def refresh_active_scenes_for_light_state(light_state_id) when is_integer(light_state_id) do
    Active.refresh_for_light_state(light_state_id)
  end

  @spec activate_scene(integer(), keyword()) :: scene_apply_result()
  def activate_scene(scene_id, opts \\ []) when is_integer(scene_id) do
    SceneApply.activate_scene(scene_id, opts)
  end

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
  def recompute_active_scene_lights(room_id, light_ids, opts \\ [])

  def recompute_active_scene_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    Active.recompute_lights(room_id, light_ids, opts)
  end

  def recompute_active_scene_lights(_room_id, _light_ids, _opts), do: {:error, :invalid_args}

  @spec recompute_active_circadian_lights(integer(), list(integer()), keyword()) ::
          scene_apply_result()
  def recompute_active_circadian_lights(room_id, light_ids, opts \\ [])

  def recompute_active_circadian_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    Active.recompute_circadian_lights(room_id, light_ids, opts)
  end

  def recompute_active_circadian_lights(_room_id, _light_ids, _opts),
    do: {:error, :invalid_args}

  # Temporary compatibility wrappers while callers migrate to the clearer
  # "recompute" naming.
  def reapply_active_scene_lights(room_id, light_ids, opts \\ []) do
    recompute_active_scene_lights(room_id, light_ids, opts)
  end

  def reapply_active_circadian_lights(room_id, light_ids, opts \\ []) do
    recompute_active_circadian_lights(room_id, light_ids, opts)
  end

  @spec replace_scene_components(struct(), list(map())) :: :ok | {:error, term()}
  def replace_scene_components(%Scene{} = scene, components) when is_list(components) do
    Components.replace(scene, components)
  end
end
