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

  def list_scenes_for_room(room_id) do
    Repo.all(from(s in Scene, where: s.room_id == ^room_id, order_by: [asc: s.name]))
  end

  def list_manual_light_states do
    LightStates.list_manual()
  end

  def list_editable_light_states do
    LightStates.list_editable()
  end

  def list_editable_light_states_with_usage do
    LightStates.list_editable_with_usage()
  end

  def get_editable_light_state(id) when is_integer(id) do
    LightStates.get_editable(id)
  end

  def get_editable_light_state(_id), do: nil

  def light_state_usages(id) when is_integer(id) do
    LightStates.usages(id)
  end

  def light_state_usages(_id), do: []

  def create_light_state(name, type, config \\ %{})

  def create_light_state(name, type, config)
      when type in [:manual, :circadian] do
    LightStates.create(name, type, config)
  end

  def create_light_state(_name, _type, _config), do: {:error, :invalid_type}

  def update_light_state(id, attrs) when is_integer(id) and is_map(attrs) do
    LightStates.update(id, attrs)
  end

  def duplicate_light_state(id) when is_integer(id) do
    LightStates.duplicate(id)
  end

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

  def get_scene(id), do: Repo.get(Scene, id)

  def update_scene(scene, attrs) do
    Persistence.update(scene, attrs)
  end

  def delete_scene(scene) do
    Persistence.delete(scene)
  end

  def refresh_active_scene(scene_id) when is_integer(scene_id) do
    Active.refresh_scene(scene_id)
  end

  def refresh_active_scenes_for_light_state(light_state_id) when is_integer(light_state_id) do
    Active.refresh_for_light_state(light_state_id)
  end

  def activate_scene(scene_id, opts \\ []) when is_integer(scene_id) do
    SceneApply.activate_scene(scene_id, opts)
  end

  def apply_scene(%Scene{} = scene, opts \\ []) do
    SceneApply.apply_scene(scene, opts)
  end

  def apply_active_scene(%Scene{} = scene, active_scene, opts \\ []) when is_list(opts) do
    SceneApply.apply_active_scene(scene, active_scene, opts)
  end

  def recompute_active_scene_lights(room_id, light_ids, opts \\ [])

  def recompute_active_scene_lights(room_id, light_ids, opts)
      when is_integer(room_id) and is_list(light_ids) do
    Active.recompute_lights(room_id, light_ids, opts)
  end

  def recompute_active_scene_lights(_room_id, _light_ids, _opts), do: {:error, :invalid_args}

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

  def replace_scene_components(%Scene{} = scene, components) when is_list(components) do
    Components.replace(scene, components)
  end
end
