defmodule Hueworks.Groups.TopologyTest do
  use ExUnit.Case, async: true

  alias Hueworks.Groups.Topology

  test "derive_subgroups and derive_supergroups use strict subset relationships" do
    member_sets = %{
      1 => MapSet.new([1, 2, 3]),
      2 => MapSet.new([1, 2]),
      3 => MapSet.new([3]),
      4 => MapSet.new([1, 2, 3, 4])
    }

    assert Topology.derive_subgroups(member_sets) == %{
             1 => [2, 3],
             2 => [],
             3 => [],
             4 => [1, 2, 3]
           }

    assert Topology.derive_supergroups(member_sets) == %{
             1 => [4],
             2 => [4, 1],
             3 => [4, 1]
           }
  end

  test "all_subgroups walks nested subgroup graphs without looping" do
    subgroups_map = %{
      1 => [2, 3],
      2 => [4],
      3 => [4, 5],
      4 => [1],
      5 => []
    }

    assert Enum.sort(Topology.all_subgroups(1, subgroups_map)) == [2, 3, 4, 5]
    assert Enum.sort(Topology.all_subgroups(subgroups_map, 2)) == [1, 3, 4, 5]
  end

  test "presentation_tree recursively decomposes scopes into maximal groups and leftover lights" do
    groups = [
      %{id: 1, name: "All", light_ids: [1, 2, 3, 4]},
      %{id: 2, name: "Upper", light_ids: [1, 2]},
      %{id: 3, name: "Left Side", light_ids: [1, 3]},
      %{id: 4, name: "Upper Accent", light_ids: [2]},
      %{id: 5, name: "Unavailable", light_ids: [1, 5]}
    ]

    topology = Topology.presentation_tree(groups, [1, 2, 3, 4, 99])

    assert Enum.map(topology.nodes, & &1.group_id) == [1]
    [all] = topology.nodes
    assert all.total_light_ids == [1, 2, 3, 4]
    assert all.light_ids == [4]
    assert Enum.map(all.children, & &1.group_id) == [3, 2]

    upper = Enum.find(all.children, &(&1.group_id == 2))
    assert upper.light_ids == [1]
    assert Enum.map(upper.children, & &1.group_id) == [4]

    upper_accent = Enum.find(upper.children, &(&1.group_id == 4))
    assert upper_accent.light_ids == [2]

    left_side = Enum.find(all.children, &(&1.group_id == 3))
    assert left_side.light_ids == [1, 3]
    assert left_side.children == []

    assert topology.ungrouped_light_ids == [99]
  end
end
