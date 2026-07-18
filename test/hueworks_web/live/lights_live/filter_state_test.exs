defmodule HueworksWeb.LightsLive.FilterStateTest do
  use ExUnit.Case, async: true

  alias HueworksWeb.LightsLive.FilterState

  test "param_updates keeps only nonblank filter params" do
    assert %{group_filter: "kitchen", light_area_filter: "5"} =
             FilterState.param_updates(%{
               "group_filter" => "kitchen",
               "light_filter" => "",
               "light_area_filter" => "5"
             })
  end

  test "event_updates normalizes area filters against known areas" do
    areas = [%{id: 1}, %{id: 2}]

    assert %{group_area_filter: 2} =
             FilterState.event_updates(
               "set_group_area_filter",
               %{"group_area_filter" => "2"},
               areas
             )

    assert %{light_area_filter: "all"} =
             FilterState.event_updates(
               "set_light_area_filter",
               %{"light_area_filter" => "999"},
               areas
             )
  end

  test "event_updates handles toggle defaults when checkbox param is absent" do
    assert %{show_disabled_groups: false} =
             FilterState.event_updates("toggle_group_disabled", %{}, [])

    assert %{show_linked_lights: true} =
             FilterState.event_updates(
               "toggle_light_linked",
               %{"show_linked_lights" => "true"},
               []
             )
  end
end
