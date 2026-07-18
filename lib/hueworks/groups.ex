defmodule Hueworks.Groups do
  @moduledoc """
  Query helpers for groups.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.HomeKit
  alias Hueworks.Groups.Topology
  alias Hueworks.Util
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.GroupLight
  alias Hueworks.Schemas.Light
  alias Hueworks.Repo

  def list_controllable_groups(include_disabled \\ false) do
    query =
      from(g in Group,
        where: is_nil(g.canonical_group_id),
        order_by: [asc: g.name]
      )

    query
    |> maybe_filter_enabled(include_disabled)
    |> Repo.all()
  end

  def get_group(id), do: Repo.get(Group, id)

  def member_light_ids(group_id) when is_integer(group_id) do
    group_id
    |> List.wrap()
    |> light_ids_by_group()
    |> Map.get(group_id, [])
  end

  def light_ids_by_group([]), do: %{}

  def light_ids_by_group(group_ids) when is_list(group_ids) do
    Repo.all(
      from(gl in GroupLight,
        where: gl.group_id in ^group_ids,
        select: {gl.group_id, gl.light_id}
      )
    )
    |> Enum.group_by(fn {group_id, _light_id} -> group_id end, fn {_group_id, light_id} ->
      light_id
    end)
  end

  def update_display_name(group, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.update(:display_name, nil, &Util.normalize_display_name/1)
      |> normalize_kelvin_attrs()

    group
    |> update_group(attrs)
    |> maybe_refresh_home_assistant_export()
    |> maybe_reload_homekit()
    |> unwrap_update_result()
  end

  def update_display_name(group, display_name) do
    update_display_name(group, %{display_name: display_name})
  end

  defp normalize_kelvin_attrs(attrs) do
    attrs
    |> Map.update(:actual_min_kelvin, nil, &Util.normalize_kelvin/1)
    |> Map.update(:actual_max_kelvin, nil, &Util.normalize_kelvin/1)
    |> Map.update(:extended_min_kelvin, nil, &Util.normalize_kelvin/1)
  end

  defp update_group(%Group{} = group, attrs) when is_map(attrs) do
    if Map.has_key?(attrs, :area_id) do
      update_group_area_cascade(group, attrs)
    else
      group
      |> Group.changeset(attrs)
      |> Repo.update()
      |> with_refresh_effects(fn updated ->
        %{group_ids: [updated.id], light_ids: []}
      end)
    end
  end

  defp update_group_area_cascade(%Group{} = group, attrs) do
    area_id = Map.get(attrs, :area_id)
    effects = area_cascade_effects(group.id)
    group_ids = effects.group_ids

    Repo.transaction(fn ->
      updated =
        group
        |> Group.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end

      update_member_lights_area!(group_ids, area_id)
      update_subgroups_area!(List.delete(group_ids, group.id), area_id)

      {updated, effects}
    end)
  end

  defp area_cascade_effects(group_id) do
    subgroup_ids =
      Topology.member_sets()
      |> Topology.derive_subgroups()
      |> then(&Topology.all_subgroups(group_id, &1))

    group_ids = [group_id | subgroup_ids] |> Enum.uniq()

    light_ids =
      group_ids
      |> light_ids_by_group()
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()

    %{group_ids: group_ids, light_ids: light_ids}
  end

  defp update_member_lights_area!(group_ids, area_id) do
    from(l in Light,
      join: gl in GroupLight,
      on: gl.light_id == l.id,
      where: gl.group_id in ^group_ids,
      update: [set: [area_id: ^area_id]]
    )
    |> Repo.update_all([])
  end

  defp update_subgroups_area!([], _area_id), do: {0, nil}

  defp update_subgroups_area!(subgroup_ids, area_id) do
    from(g in Group,
      where: g.id in ^subgroup_ids,
      update: [set: [area_id: ^area_id]]
    )
    |> Repo.update_all([])
  end

  defp with_refresh_effects({:ok, %Group{} = group}, build_effects)
       when is_function(build_effects, 1) do
    {:ok, {group, build_effects.(group)}}
  end

  defp with_refresh_effects(other, _build_effects), do: other

  defp maybe_refresh_home_assistant_export({:ok, {%Group{}, effects}} = result) do
    effects.group_ids
    |> Enum.uniq()
    |> Enum.each(&HomeAssistantExport.refresh_group/1)

    effects.light_ids
    |> Enum.uniq()
    |> Enum.each(&HomeAssistantExport.refresh_light/1)

    result
  end

  defp maybe_refresh_home_assistant_export(result), do: result

  defp maybe_reload_homekit({:ok, {%Group{}, _effects}} = result) do
    HomeKit.reload()
    result
  end

  defp maybe_reload_homekit(result), do: result

  defp unwrap_update_result({:ok, {%Group{} = group, _effects}}), do: {:ok, group}
  defp unwrap_update_result(other), do: other

  defp maybe_filter_enabled(query, true), do: query

  defp maybe_filter_enabled(query, false) do
    from(g in query, where: g.enabled == true)
  end
end
