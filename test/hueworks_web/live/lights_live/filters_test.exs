defmodule HueworksWeb.LightsLive.FiltersTest do
  use ExUnit.Case, async: true

  alias HueworksWeb.LightsLive.Filters

  test "filter_entities applies source room and disabled filters together" do
    entities = [
      %{id: 1, source: :hue, room_id: 10, enabled: true},
      %{id: 2, source: :hue, room_id: 11, enabled: false},
      %{id: 3, source: :ha, room_id: 10, enabled: true},
      %{id: 4, source: :hue, room_id: nil, enabled: true}
    ]

    assert Enum.map(Filters.filter_entities(entities, "hue", 10, false), & &1.id) == [1]
    assert Enum.map(Filters.filter_entities(entities, "all", "unassigned", false), & &1.id) == [4]
    assert Enum.map(Filters.filter_entities(entities, "hue", 11, true), & &1.id) == [2]
  end

  test "filter_lights excludes linked lights unless requested" do
    lights = [
      %{id: 1, source: :hue, room_id: 10, enabled: true, canonical_light_id: nil},
      %{id: 2, source: :hue, room_id: 10, enabled: true, canonical_light_id: 1}
    ]

    assert Enum.map(Filters.filter_lights(lights, "all", "all", false, false), & &1.id) == [1]
    assert Enum.map(Filters.filter_lights(lights, "all", "all", false, true), & &1.id) == [1, 2]
  end
end
