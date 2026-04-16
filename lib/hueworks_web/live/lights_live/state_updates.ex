defmodule HueworksWeb.LightsLive.StateUpdates do
  @moduledoc false

  alias HueworksWeb.LightsLive.Actions.Result
  alias HueworksWeb.LightsLive.DisplayState

  def apply_action_result(assigns, %Result{target_type: :light, target_id: id, attrs: attrs, status: status}) do
    %{
      light_state: merge_light_state(assigns.light_state, id, attrs),
      status: status
    }
  end

  def apply_action_result(assigns, %Result{target_type: :group, target_id: id, attrs: attrs, status: status}) do
    %{
      group_state: merge_group_state(assigns.group_state, id, attrs),
      status: status
    }
  end

  def replace_control_state(assigns, :light, id, state) when is_integer(id) and is_map(state) do
    replaced_state =
      assigns.light_state
      |> Map.get(id, %{})
      |> DisplayState.replace_light(light_for_id(assigns.lights, id), state)

    %{light_state: Map.put(assigns.light_state, id, replaced_state)}
  end

  def replace_control_state(assigns, :group, id, state) when is_integer(id) and is_map(state) do
    %{group_state: Map.update(assigns.group_state, id, state, &DisplayState.replace(&1, state))}
  end

  def put_active_scene(assigns, room_id, scene_id) when is_integer(room_id) do
    active_scene_by_room = assigns.active_scene_by_room || %{}

    active_scene_by_room =
      case scene_id do
        value when is_integer(value) -> Map.put(active_scene_by_room, room_id, value)
        _ -> Map.delete(active_scene_by_room, room_id)
      end

    %{active_scene_by_room: active_scene_by_room}
  end

  defp merge_light_state(light_state, light_id, attrs)
       when is_integer(light_id) and is_map(attrs) do
    Map.update(light_state, light_id, attrs, &DisplayState.merge(&1, attrs))
  end

  defp merge_group_state(group_state, group_id, attrs)
       when is_integer(group_id) and is_map(attrs) do
    Map.update(group_state, group_id, attrs, &DisplayState.merge(&1, attrs))
  end

  defp light_for_id(lights, id) do
    Enum.find(lights, &(&1.id == id))
  end
end
