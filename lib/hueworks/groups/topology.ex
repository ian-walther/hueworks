defmodule Hueworks.Groups.Topology do
  @moduledoc """
  Group topology helpers for deriving subgroup relationships.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight

  def member_sets do
    groups = Repo.all(from(g in Group, where: is_nil(g.canonical_group_id)))

    memberships =
      Repo.all(
        from(gl in GroupLight,
          join: g in Group,
          on: g.id == gl.group_id,
          where: is_nil(g.canonical_group_id),
          select: {gl.group_id, gl.light_id}
        )
      )

    groups
    |> Enum.reduce(%{}, fn group, acc -> Map.put(acc, group.id, MapSet.new()) end)
    |> add_memberships(memberships)
  end

  def derive_subgroups(member_sets) when is_map(member_sets) do
    ids = Map.keys(member_sets)
    identical = find_identical_memberships(member_sets)

    if identical != [] do
      Logger.warning("Identical group memberships detected: #{format_ids(identical)}")
    end

    Enum.reduce(ids, %{}, fn id, acc ->
      base = Map.get(member_sets, id, MapSet.new())

      subgroups =
        ids
        |> Enum.reject(&(&1 == id))
        |> Enum.filter(fn other_id ->
          other = Map.get(member_sets, other_id, MapSet.new())

          MapSet.size(other) > 0 and MapSet.subset?(other, base) and
            not MapSet.equal?(other, base)
        end)

      Map.put(acc, id, subgroups)
    end)
  end

  def derive_supergroups(member_sets) when is_map(member_sets) do
    subgroups = derive_subgroups(member_sets)

    Enum.reduce(subgroups, %{}, fn {group_id, children}, acc ->
      Enum.reduce(children, acc, fn child_id, inner ->
        Map.update(inner, child_id, [group_id], &[group_id | &1])
      end)
    end)
  end

  def all_subgroups(group_id, subgroups_map) when is_integer(group_id) do
    walk_subgroups([group_id], subgroups_map, MapSet.new())
    |> MapSet.delete(group_id)
    |> MapSet.to_list()
  end

  def all_subgroups(subgroups_map, group_id) when is_integer(group_id) do
    all_subgroups(group_id, subgroups_map)
  end

  defp walk_subgroups([], _map, visited), do: visited

  defp walk_subgroups([id | rest], map, visited) do
    if MapSet.member?(visited, id) do
      walk_subgroups(rest, map, visited)
    else
      children = Map.get(map, id, [])
      walk_subgroups(children ++ rest, map, MapSet.put(visited, id))
    end
  end

  defp add_memberships(base, memberships) do
    Enum.reduce(memberships, base, fn {group_id, light_id}, acc ->
      Map.update(acc, group_id, MapSet.new([light_id]), &MapSet.put(&1, light_id))
    end)
  end

  defp find_identical_memberships(member_sets) do
    member_sets
    |> Enum.group_by(fn {_id, set} -> MapSet.to_list(set) |> Enum.sort() end, fn {id, _} -> id end)
    |> Enum.filter(fn {_set, ids} -> length(ids) > 1 end)
    |> Enum.map(fn {_set, ids} -> ids end)
  end

  defp format_ids(groups) do
    groups
    |> Enum.map(fn ids -> Enum.map(ids, &to_string/1) end)
    |> inspect()
  end
end
