defmodule Hueworks.SceneBuilderTest do
  use ExUnit.Case, async: true

  alias Hueworks.Scenes.Builder

  defp room_lights do
    [
      %{id: 1, name: "Lamp"},
      %{id: 2, name: "Ceiling"},
      %{id: 3, name: "Desk"}
    ]
  end

  defp groups do
    [
      %{id: 10, name: "All", light_ids: [1, 2, 3]},
      %{id: 11, name: "Work", light_ids: [1, 3]},
      %{id: 12, name: "Empty", light_ids: []}
    ]
  end

  test "canonical lights and groups are excluded from available lists and validation" do
    lights = [
      %{id: 1, name: "Lamp"},
      %{id: 2, name: "Ceiling", canonical_light_id: 99},
      %{id: 3, name: "Desk"}
    ]

    groups = [
      %{id: 10, name: "All", light_ids: [1, 2, 3]},
      %{id: 11, name: "Work", light_ids: [1, 3], canonical_group_id: 55}
    ]

    state = Builder.build(lights, groups, [%{light_ids: [1, 3]}])

    assert state.room_light_ids == [1, 3]
    assert Enum.map(state.available_lights, & &1.id) == []
    refute Enum.any?(state.available_groups, &(&1.id == 11))
    assert state.unassigned_light_ids == []
    assert state.valid?
  end

  test "build reports available lights and groups when nothing assigned" do
    state = Builder.build(room_lights(), groups(), [%{light_ids: []}])

    assert Enum.map(state.available_lights, & &1.id) == [1, 2, 3]
    assert Enum.map(state.available_groups, & &1.id) == [10, 11]
    assert state.unassigned_light_ids == [1, 2, 3]
    refute state.valid?
  end

  test "assigned lights are removed from available lists" do
    components = [%{light_ids: [1]}]
    state = Builder.build(room_lights(), groups(), components)

    assert Enum.map(state.available_lights, & &1.id) == [2, 3]
    assert Enum.map(state.available_groups, & &1.id) == []
    assert state.unassigned_light_ids == [2, 3]
  end

  test "groups remain available when none of their lights are assigned" do
    components = [%{light_ids: [2]}]
    state = Builder.build(room_lights(), groups(), components)

    assert Enum.map(state.available_groups, & &1.id) == [11]
  end

  test "valid? requires all room lights assigned exactly once" do
    state = Builder.build(room_lights(), groups(), [%{light_ids: [1, 2, 3]}])
    assert state.valid?
    assert state.duplicate_light_ids == []
  end

  test "duplicate light assignments invalidate the state" do
    state =
      Builder.build(room_lights(), groups(), [
        %{light_ids: [1, 2]},
        %{light_ids: [2, 3]}
      ])

    refute state.valid?
    assert state.duplicate_light_ids == [2]
  end

  test "assigned_light_ids returns unique ids" do
    assigned = Builder.assigned_light_ids([%{light_ids: [1, 1, 2]}, %{light_ids: [2, 3]}])
    assert MapSet.equal?(assigned, MapSet.new([1, 2, 3]))
  end
end
