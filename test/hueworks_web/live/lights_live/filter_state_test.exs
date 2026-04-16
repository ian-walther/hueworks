defmodule HueworksWeb.LightsLive.FilterStateTest do
  use ExUnit.Case, async: true

  alias HueworksWeb.LightsLive.FilterState

  test "param_updates keeps only nonblank filter params" do
    assert %{group_filter: "kitchen", light_room_filter: "5"} =
             FilterState.param_updates(%{
               "group_filter" => "kitchen",
               "light_filter" => "",
               "light_room_filter" => "5"
             })
  end

  test "event_updates normalizes room filters against known rooms" do
    rooms = [%{id: 1}, %{id: 2}]

    assert %{group_room_filter: 2} =
             FilterState.event_updates("set_group_room_filter", %{"group_room_filter" => "2"}, rooms)

    assert %{light_room_filter: "all"} =
             FilterState.event_updates("set_light_room_filter", %{"light_room_filter" => "999"}, rooms)
  end

  test "event_updates handles toggle defaults when checkbox param is absent" do
    assert %{show_disabled_groups: false} =
             FilterState.event_updates("toggle_group_disabled", %{}, [])

    assert %{show_linked_lights: true} =
             FilterState.event_updates("toggle_light_linked", %{"show_linked_lights" => "true"}, [])
  end
end
