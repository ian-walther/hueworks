defmodule HueworksWeb.LightsLive.Loader do
  @moduledoc false

  alias Hueworks.Groups
  alias Hueworks.Lights
  alias Hueworks.Rooms
  alias HueworksWeb.FilterPrefs
  alias HueworksWeb.LightsLive.DisplayState
  alias Hueworks.Util

  def mount_assigns(params, filter_session_id) do
    prefs = FilterPrefs.get(filter_session_id)
    snapshot = snapshot()

    group_filter = Util.parse_filter(prefs[:group_filter] || params["group_filter"])
    light_filter = Util.parse_filter(prefs[:light_filter] || params["light_filter"])

    group_room_filter =
      Util.parse_room_filter(prefs[:group_room_filter] || params["group_room_filter"])
      |> Util.normalize_room_filter(snapshot.rooms)

    light_room_filter =
      Util.parse_room_filter(prefs[:light_room_filter] || params["light_room_filter"])
      |> Util.normalize_room_filter(snapshot.rooms)

    if is_binary(filter_session_id) do
      FilterPrefs.update(filter_session_id, %{
        group_room_filter: group_room_filter,
        light_room_filter: light_room_filter
      })
    end

    Map.merge(snapshot, %{
      filter_session_id: filter_session_id,
      group_filter: group_filter,
      light_filter: light_filter,
      group_room_filter: group_room_filter,
      light_room_filter: light_room_filter,
      status: nil,
      show_disabled_groups: prefs[:show_disabled_groups] || false,
      show_disabled_lights: prefs[:show_disabled_lights] || false,
      show_linked_lights: prefs[:show_linked_lights] || false
    })
  end

  def reload_assigns(assigns) do
    snapshot = snapshot()

    Map.merge(snapshot, %{
      group_room_filter: Util.normalize_room_filter(assigns.group_room_filter, snapshot.rooms),
      light_room_filter: Util.normalize_room_filter(assigns.light_room_filter, snapshot.rooms)
    })
  end

  defp snapshot do
    groups = Groups.list_controllable_groups(true)
    lights = Lights.list_controllable_lights(true, true)

    %{
      rooms: Rooms.list_rooms(),
      groups: groups,
      lights: lights,
      group_state: DisplayState.build_group_state(groups),
      light_state: DisplayState.build_light_state(lights)
    }
  end
end
