defmodule Hueworks.Groups.Topology do
  @moduledoc """
  Group topology helpers for deriving subgroup relationships.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight

  @type member_set_map :: %{optional(integer()) => MapSet.t(integer())}
  @type subgroup_map :: %{optional(integer()) => list(integer())}
  @type presentation_node :: %{
          group: map(),
          group_id: integer(),
          total_light_ids: list(integer()),
          light_ids: list(integer()),
          children: list(presentation_node())
        }
  @type presentation_tree :: %{
          nodes: list(presentation_node()),
          ungrouped_light_ids: list(integer())
        }

  @spec member_sets() :: member_set_map()
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

  @spec derive_subgroups(member_set_map()) :: subgroup_map()
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

  @spec derive_supergroups(member_set_map()) :: subgroup_map()
  def derive_supergroups(member_sets) when is_map(member_sets) do
    subgroups = derive_subgroups(member_sets)

    Enum.reduce(subgroups, %{}, fn {group_id, children}, acc ->
      Enum.reduce(children, acc, fn child_id, inner ->
        Map.update(inner, child_id, [group_id], &[group_id | &1])
      end)
    end)
  end

  @spec all_subgroups(integer(), subgroup_map()) :: list(integer())
  def all_subgroups(group_id, subgroups_map) when is_integer(group_id) do
    walk_subgroups([group_id], subgroups_map, [])
    |> Enum.reverse()
    |> Enum.uniq()
    |> List.delete(group_id)
  end

  def all_subgroups(subgroups_map, group_id) when is_integer(group_id) do
    all_subgroups(group_id, subgroups_map)
  end

  @spec presentation_tree(list(map()), list(integer())) :: presentation_tree()
  def presentation_tree(groups, selected_light_ids) when is_list(groups) do
    selected_light_ids =
      selected_light_ids
      |> normalize_light_ids()
      |> MapSet.new()

    groups
    |> complete_group_entries(selected_light_ids)
    |> decompose_scope(selected_light_ids, nil)
  end

  def presentation_tree(_groups, _selected_light_ids), do: %{nodes: [], ungrouped_light_ids: []}

  defp walk_subgroups([], _map, visited), do: visited

  defp walk_subgroups([id | rest], map, visited) do
    if id in visited do
      walk_subgroups(rest, map, visited)
    else
      children = Map.get(map, id, [])
      walk_subgroups(children ++ rest, map, [id | visited])
    end
  end

  defp complete_group_entries(groups, selected_light_ids) do
    groups
    |> Enum.flat_map(fn group ->
      id = group_id(group)
      light_ids = group |> group_light_ids() |> Enum.sort()
      light_set = MapSet.new(light_ids)

      if is_integer(id) and light_ids != [] and MapSet.subset?(light_set, selected_light_ids) do
        [%{id: id, group: group, light_ids: light_ids, light_set: light_set}]
      else
        []
      end
    end)
  end

  defp strict_superset?(possible_parent, child) do
    MapSet.size(possible_parent) > MapSet.size(child) and MapSet.subset?(child, possible_parent)
  end

  defp decompose_scope(group_entries, scope_light_set, parent_entry) do
    selected_entries =
      group_entries
      |> candidate_entries(scope_light_set, parent_entry)
      |> maximal_entries()
      |> sort_entries()

    covered_light_ids =
      selected_entries
      |> Enum.flat_map(&MapSet.to_list(&1.light_set))
      |> MapSet.new()

    %{
      nodes:
        Enum.map(selected_entries, fn entry ->
          child_scope = decompose_scope(group_entries, entry.light_set, entry)

          %{
            group: entry.group,
            group_id: entry.id,
            total_light_ids: entry.light_ids,
            light_ids: child_scope.ungrouped_light_ids,
            children: child_scope.nodes
          }
        end),
      ungrouped_light_ids:
        scope_light_set
        |> MapSet.difference(covered_light_ids)
        |> MapSet.to_list()
        |> Enum.sort()
    }
  end

  defp candidate_entries(group_entries, scope_light_set, nil) do
    Enum.filter(group_entries, &MapSet.subset?(&1.light_set, scope_light_set))
  end

  defp candidate_entries(group_entries, scope_light_set, parent_entry) do
    group_entries
    |> Enum.reject(&(&1.id == parent_entry.id))
    |> Enum.filter(fn entry ->
      MapSet.size(entry.light_set) < MapSet.size(scope_light_set) and
        MapSet.subset?(entry.light_set, scope_light_set)
    end)
  end

  defp maximal_entries(entries) do
    Enum.reject(entries, fn entry ->
      Enum.any?(entries, fn other ->
        other.id != entry.id and strict_superset?(other.light_set, entry.light_set)
      end)
    end)
  end

  defp sort_entries(entries) do
    Enum.sort_by(entries, fn entry ->
      {-MapSet.size(entry.light_set), entry |> entry_name() |> String.downcase(), entry.id}
    end)
  end

  defp entry_name(%{group: group}) do
    Hueworks.Util.display_name(group)
  end

  defp group_id(%{id: id}) when is_integer(id), do: id
  defp group_id(%{"id" => id}) when is_integer(id), do: id
  defp group_id(_group), do: nil

  defp group_light_ids(%{light_ids: light_ids}), do: normalize_light_ids(light_ids)
  defp group_light_ids(%{"light_ids" => light_ids}), do: normalize_light_ids(light_ids)
  defp group_light_ids(_group), do: []

  defp normalize_light_ids(light_ids) do
    light_ids
    |> List.wrap()
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
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
