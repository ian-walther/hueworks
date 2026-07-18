defmodule HueworksWeb.LightsLive.Loader do
  @moduledoc false

  alias Hueworks.ActiveScenes
  alias Hueworks.Groups
  alias Hueworks.Lights
  alias Hueworks.Areas
  alias HueworksWeb.FilterPrefs
  alias HueworksWeb.LightsLive.DisplayState
  alias Hueworks.Util

  def mount_assigns(params, filter_session_id) do
    prefs = FilterPrefs.get(filter_session_id)
    snapshot = snapshot()

    group_filter = Util.parse_filter(prefs[:group_filter] || params["group_filter"])
    light_filter = Util.parse_filter(prefs[:light_filter] || params["light_filter"])

    group_area_filter =
      Util.parse_area_filter(prefs[:group_area_filter] || params["group_area_filter"])
      |> Util.normalize_area_filter(snapshot.areas)

    light_area_filter =
      Util.parse_area_filter(prefs[:light_area_filter] || params["light_area_filter"])
      |> Util.normalize_area_filter(snapshot.areas)

    if is_binary(filter_session_id) do
      FilterPrefs.update(filter_session_id, %{
        group_area_filter: group_area_filter,
        light_area_filter: light_area_filter
      })
    end

    Map.merge(snapshot, %{
      filter_session_id: filter_session_id,
      group_filter: group_filter,
      light_filter: light_filter,
      group_area_filter: group_area_filter,
      light_area_filter: light_area_filter,
      status: nil,
      show_disabled_groups: prefs[:show_disabled_groups] || false,
      show_disabled_lights: prefs[:show_disabled_lights] || false,
      show_linked_lights: prefs[:show_linked_lights] || false
    })
  end

  def reload_assigns(assigns) do
    snapshot = snapshot()

    Map.merge(snapshot, %{
      group_area_filter: Util.normalize_area_filter(assigns.group_area_filter, snapshot.areas),
      light_area_filter: Util.normalize_area_filter(assigns.light_area_filter, snapshot.areas)
    })
  end

  defp snapshot do
    groups = Groups.list_controllable_groups(true)
    lights = Lights.list_controllable_lights(true, true)

    %{
      areas: Areas.list_areas(),
      groups: groups,
      lights: lights,
      active_scene_by_area: active_scene_by_area(),
      group_state: DisplayState.build_group_state(groups),
      light_state: DisplayState.build_light_state(lights)
    }
  end

  defp active_scene_by_area do
    ActiveScenes.list_active_scenes()
    |> Map.new(fn active_scene -> {active_scene.area_id, active_scene.scene_id} end)
  end
end
