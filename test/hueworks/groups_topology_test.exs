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
end
