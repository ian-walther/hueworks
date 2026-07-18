defmodule Hueworks.Import.ReimportApply do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.{Duplicates, EntityAttrs, EntityMatch, Identifiers, Normalize, Areas}
  alias Hueworks.HomeAssistant.Export, as: HomeAssistantExport
  alias Hueworks.HomeKit
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, SceneComponentLight}

  def apply(bridge, normalized, plan) do
    case Repo.transaction(fn -> apply!(bridge, normalized, plan) end) do
      {:ok, side_effects} ->
        run_post_commit_effects(side_effects)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply!(bridge, normalized, plan) do
    areas = Normalize.fetch(normalized, :areas) || []

    lights =
      normalized
      |> Normalize.fetch(:lights)
      |> Kernel.||([])
      |> Duplicates.reject_hueworks_exported()

    groups =
      normalized
      |> Normalize.fetch(:groups)
      |> Kernel.||([])
      |> Duplicates.reject_hueworks_exported()

    memberships = Normalize.fetch(normalized, :memberships) || %{}
    plan_areas = Normalize.fetch(plan, :areas) || %{}
    plan_lights = Normalize.fetch(plan, :lights) || %{}
    plan_groups = Normalize.fetch(plan, :groups) || %{}

    existing_lights = list_bridge_lights(bridge.id)
    existing_groups = list_bridge_groups(bridge.id)

    duplicate_light_targets = Duplicates.light_targets(lights)

    needed_area_source_ids =
      needed_area_source_ids(
        lights,
        groups,
        existing_lights,
        existing_groups,
        plan_lights,
        plan_groups
      )

    area_map = upsert_needed_areas(areas, plan_areas, needed_area_source_ids)

    light_result =
      apply_lights(
        bridge,
        lights,
        area_map,
        plan_lights,
        existing_lights,
        duplicate_light_targets
      )

    group_result =
      apply_groups(bridge, groups, area_map, plan_groups, existing_groups, light_result)

    refresh_group_lights(
      groups,
      memberships,
      light_result.source_id_to_db_id,
      group_result.source_id_to_db_id
    )

    delete_missing_hidden_duplicates(
      bridge,
      lights,
      groups
    )

    apply_selected_resolutions!(bridge, plan_lights, plan_groups)
  end

  defp list_bridge_lights(bridge_id),
    do: Repo.all(from(l in Light, where: l.bridge_id == ^bridge_id))

  defp list_bridge_groups(bridge_id),
    do: Repo.all(from(g in Group, where: g.bridge_id == ^bridge_id))

  defp needed_area_source_ids(
         lights,
         groups,
         existing_lights,
         existing_groups,
         plan_lights,
         plan_groups
       ) do
    light_ids =
      lights
      |> Enum.filter(fn light ->
        source_id = source_id(light)

        selected?(plan_lights, source_id) and
          not hidden_duplicate_resolution?(plan_lights, source_id) and
          is_nil(EntityMatch.match_existing(existing_lights, light, :light))
      end)
      |> Enum.map(&area_source_id/1)

    group_ids =
      groups
      |> Enum.filter(fn group ->
        source_id = source_id(group)

        selected?(plan_groups, source_id) and
          not hidden_duplicate_resolution?(plan_groups, source_id) and
          is_nil(EntityMatch.match_existing(existing_groups, group, :group))
      end)
      |> Enum.map(&area_source_id/1)

    (light_ids ++ group_ids)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp upsert_needed_areas(areas, plan_areas, needed_area_source_ids) do
    Enum.reduce(areas, %{}, fn area, acc ->
      source_id = source_id(area)

      if is_binary(source_id) and MapSet.member?(needed_area_source_ids, source_id) do
        case Areas.upsert(area, Normalize.fetch(plan_areas, source_id) || %{}) do
          nil -> acc
          area_id -> Map.put(acc, source_id, area_id)
        end
      else
        acc
      end
    end)
  end

  defp apply_lights(bridge, lights, area_map, plan_lights, existing_lights, duplicate_targets) do
    initial = %{
      source_id_to_db_id: %{},
      source_id_to_canonical_db_id: %{},
      seen_existing_ids: MapSet.new()
    }

    Enum.reduce(lights, initial, fn light, acc ->
      source_id = source_id(light)

      cond do
        not is_binary(source_id) ->
          acc

        not selected?(plan_lights, source_id) ->
          acc

        true ->
          case EntityMatch.match_existing(existing_lights, light, :light) do
            :ambiguous ->
              acc

            nil ->
              {record, canonical_id, hidden_duplicate?} =
                case Map.get(duplicate_targets, source_id) do
                  target_id when is_integer(target_id) ->
                    if import_real_resolution?(plan_lights, source_id) do
                      record =
                        insert_light!(
                          bridge,
                          light,
                          Areas.target_id_for(light, area_map, plan_lights)
                        )

                      {record, record.id, false}
                    else
                      unless hidden_duplicate_resolution?(plan_lights, source_id) do
                        Repo.rollback({:duplicate_classification_changed, :light, source_id})
                      end

                      record = import_hidden_duplicate_light!(bridge, light, target_id)
                      {record, target_id, true}
                    end

                  nil ->
                    if hidden_duplicate_resolution?(plan_lights, source_id) do
                      Repo.rollback({:invalid_duplicate, :light, source_id})
                    else
                      record =
                        insert_light!(
                          bridge,
                          light,
                          Areas.target_id_for(light, area_map, plan_lights)
                        )

                      {record, record.id, false}
                    end
                end

              seen_existing_ids =
                if hidden_duplicate? do
                  MapSet.put(acc.seen_existing_ids, record.id)
                else
                  acc.seen_existing_ids
                end

              %{
                acc
                | source_id_to_db_id: Map.put(acc.source_id_to_db_id, source_id, record.id),
                  source_id_to_canonical_db_id:
                    Map.put(acc.source_id_to_canonical_db_id, source_id, canonical_id),
                  seen_existing_ids: seen_existing_ids
              }

            %Light{} = existing ->
              record = refresh_light!(bridge, existing, light)
              canonical_id = record.canonical_light_id || record.id

              %{
                acc
                | source_id_to_db_id: Map.put(acc.source_id_to_db_id, source_id, record.id),
                  source_id_to_canonical_db_id:
                    Map.put(acc.source_id_to_canonical_db_id, source_id, canonical_id),
                  seen_existing_ids: MapSet.put(acc.seen_existing_ids, record.id)
              }
          end
      end
    end)
  end

  defp apply_groups(bridge, groups, area_map, plan_groups, existing_groups, light_result) do
    initial = %{source_id_to_db_id: %{}, seen_existing_ids: MapSet.new()}

    Enum.reduce(groups, initial, fn group, acc ->
      source_id = source_id(group)

      cond do
        not is_binary(source_id) ->
          acc

        not selected?(plan_groups, source_id) ->
          acc

        true ->
          case EntityMatch.match_existing(existing_groups, group, :group) do
            :ambiguous ->
              acc

            nil ->
              {record, hidden_duplicate?} =
                case Duplicates.group_target(group, light_result.source_id_to_canonical_db_id) do
                  canonical_group_id when is_integer(canonical_group_id) ->
                    if import_real_resolution?(plan_groups, source_id) do
                      {insert_group!(
                         bridge,
                         group,
                         Areas.target_id_for(group, area_map, plan_groups),
                         nil
                       ), false}
                    else
                      unless hidden_duplicate_resolution?(plan_groups, source_id) do
                        Repo.rollback({:duplicate_classification_changed, :group, source_id})
                      end

                      {insert_group!(bridge, group, nil, canonical_group_id), true}
                    end

                  _ ->
                    if hidden_duplicate_resolution?(plan_groups, source_id) do
                      Repo.rollback({:invalid_duplicate, :group, source_id})
                    else
                      {insert_group!(
                         bridge,
                         group,
                         Areas.target_id_for(group, area_map, plan_groups),
                         nil
                       ), false}
                    end
                end

              seen_existing_ids =
                if hidden_duplicate? do
                  MapSet.put(acc.seen_existing_ids, record.id)
                else
                  acc.seen_existing_ids
                end

              %{
                acc
                | source_id_to_db_id: Map.put(acc.source_id_to_db_id, source_id, record.id),
                  seen_existing_ids: seen_existing_ids
              }

            %Group{} = existing ->
              record = refresh_group!(bridge, existing, group)

              %{
                acc
                | source_id_to_db_id: Map.put(acc.source_id_to_db_id, source_id, record.id),
                  seen_existing_ids: MapSet.put(acc.seen_existing_ids, record.id)
              }
          end
      end
    end)
  end

  defp refresh_group_lights(groups, memberships, light_map, group_map) do
    membership_groups =
      memberships
      |> Normalize.fetch(:group_lights)
      |> Kernel.||([])
      |> Enum.group_by(
        &Normalize.normalize_source_id(Normalize.fetch(&1, :group_source_id)),
        &Normalize.normalize_source_id(Normalize.fetch(&1, :light_source_id))
      )

    groups_by_source_id =
      Enum.reduce(groups, %{}, fn group, acc ->
        case source_id(group) do
          nil -> acc
          group_source_id -> Map.put(acc, group_source_id, group)
        end
      end)

    Enum.each(group_map, fn {group_source_id, group_id} ->
      cond do
        Map.has_key?(membership_groups, group_source_id) ->
          refresh_group_membership(
            group_id,
            Map.fetch!(membership_groups, group_source_id),
            light_map
          )

        upstream_group_members_empty?(Map.get(groups_by_source_id, group_source_id)) ->
          replace_group_lights(group_id, [])

        true ->
          :ok
      end
    end)
  end

  defp refresh_group_membership(group_id, light_source_ids, light_map)
       when is_integer(group_id) do
    light_ids = Enum.map(light_source_ids, &Map.get(light_map, &1))

    if Enum.all?(light_ids, &is_integer/1) do
      replace_group_lights(group_id, light_ids)
    end
  end

  defp refresh_group_membership(_group_id, _light_source_ids, _light_map), do: :ok

  defp replace_group_lights(group_id, light_ids) when is_integer(group_id) do
    Repo.delete_all(from(gl in GroupLight, where: gl.group_id == ^group_id))

    light_ids
    |> Enum.uniq()
    |> Enum.each(fn light_id ->
      %GroupLight{}
      |> GroupLight.changeset(%{group_id: group_id, light_id: light_id})
      |> Repo.insert!(on_conflict: :nothing, conflict_target: [:group_id, :light_id])
    end)
  end

  defp replace_group_lights(_group_id, _light_ids), do: :ok

  defp upstream_group_members_empty?(nil), do: false

  defp upstream_group_members_empty?(group) do
    metadata = Normalize.fetch(group, :metadata) || %{}

    case Normalize.fetch(metadata, :members) do
      members when is_list(members) -> members == []
      _ -> false
    end
  end

  defp insert_light!(bridge, light, area_id) do
    %Light{}
    |> Light.changeset(bridge |> EntityAttrs.light_attrs(light) |> Map.put(:area_id, area_id))
    |> Repo.insert!()
  end

  defp import_hidden_duplicate_light!(bridge, light, canonical_light_id) do
    attrs =
      bridge
      |> EntityAttrs.light_attrs(light)
      |> EntityAttrs.hidden_duplicate_overlay(canonical_light_id, :light)

    case Repo.get_by(Light, bridge_id: bridge.id, source_id: attrs.source_id) do
      nil ->
        %Light{}
        |> Light.changeset(attrs)
        |> Repo.insert!()

      existing ->
        existing
        |> Light.changeset(attrs)
        |> Repo.update!()
    end
  end

  defp refresh_light!(bridge, existing, light) do
    existing
    |> Light.changeset(EntityAttrs.light_attrs(bridge, light))
    |> Repo.update!()
  end

  defp insert_group!(bridge, group, area_id, canonical_group_id) do
    attrs =
      bridge
      |> EntityAttrs.group_attrs(group)
      |> Map.put(:area_id, area_id)

    attrs =
      if is_integer(canonical_group_id) do
        EntityAttrs.hidden_duplicate_overlay(attrs, canonical_group_id, :group)
      else
        attrs
      end

    %Group{}
    |> Group.changeset(attrs)
    |> Repo.insert!()
  end

  defp refresh_group!(bridge, existing, group) do
    existing
    |> Group.changeset(EntityAttrs.group_attrs(bridge, group))
    |> Repo.update!()
  end

  defp delete_missing_hidden_duplicates(bridge, lights, groups) do
    keep_light_ids =
      bridge.id
      |> list_hidden_duplicate_lights()
      |> present_hidden_duplicate_ids(lights, :light)

    keep_group_ids =
      bridge.id
      |> list_hidden_duplicate_groups()
      |> present_hidden_duplicate_ids(groups, :group)

    Repo.delete_all(
      from(l in Light,
        where:
          l.bridge_id == ^bridge.id and not is_nil(l.canonical_light_id) and l.enabled == false and
            is_nil(l.area_id) and l.id not in ^keep_light_ids
      )
    )

    Repo.delete_all(
      from(g in Group,
        where:
          g.bridge_id == ^bridge.id and not is_nil(g.canonical_group_id) and g.enabled == false and
            is_nil(g.area_id) and g.id not in ^keep_group_ids
      )
    )
  end

  defp list_hidden_duplicate_lights(bridge_id) do
    Repo.all(
      from(l in Light,
        where:
          l.bridge_id == ^bridge_id and not is_nil(l.canonical_light_id) and l.enabled == false and
            is_nil(l.area_id)
      )
    )
  end

  defp list_hidden_duplicate_groups(bridge_id) do
    Repo.all(
      from(g in Group,
        where:
          g.bridge_id == ^bridge_id and not is_nil(g.canonical_group_id) and g.enabled == false and
            is_nil(g.area_id)
      )
    )
  end

  defp present_hidden_duplicate_ids(records, incoming, type) do
    records
    |> Enum.filter(&upstream_present?(&1, incoming, type))
    |> Enum.map(& &1.id)
  end

  defp upstream_present?(record, incoming, type) do
    external_id = record.external_id

    Enum.any?(incoming, fn entry ->
      source_id(entry) == record.source_id or
        (is_binary(external_id) and incoming_external_id(entry, type) == external_id)
    end)
  end

  defp incoming_external_id(entry, :light), do: Identifiers.light_external_id(entry)
  defp incoming_external_id(entry, :group), do: Identifiers.group_external_id(entry)

  defp apply_selected_resolutions!(bridge, plan_lights, plan_groups) do
    disable_light_entries = resolution_entries(plan_lights, "disable")
    disable_group_entries = resolution_entries(plan_groups, "disable")
    delete_light_entries = resolution_entries(plan_lights, "delete")
    delete_group_entries = resolution_entries(plan_groups, "delete")

    validate_resolution_targets!(bridge, :light, disable_light_entries ++ delete_light_entries)
    validate_resolution_targets!(bridge, :group, disable_group_entries ++ delete_group_entries)

    disabled_light_ids = disable_lights!(bridge, entry_source_ids(disable_light_entries))
    disabled_group_ids = disable_groups!(bridge, entry_source_ids(disable_group_entries))
    deleted_group_ids = delete_groups!(bridge, entry_source_ids(delete_group_entries))
    deleted_light_ids = delete_lights!(bridge, entry_source_ids(delete_light_entries))

    remove_effects(:light, disabled_light_ids ++ deleted_light_ids) ++
      remove_effects(:group, disabled_group_ids ++ deleted_group_ids)
  end

  defp disable_lights!(_bridge, []), do: []

  defp disable_lights!(bridge, source_ids) do
    light_ids = light_ids_for_source_ids(bridge, source_ids)

    Repo.update_all(
      from(l in Light, where: l.bridge_id == ^bridge.id and l.source_id in ^source_ids),
      set: [enabled: false]
    )

    light_ids
  end

  defp disable_groups!(_bridge, []), do: []

  defp disable_groups!(bridge, source_ids) do
    group_ids = group_ids_for_source_ids(bridge, source_ids)

    Repo.update_all(
      from(g in Group, where: g.bridge_id == ^bridge.id and g.source_id in ^source_ids),
      set: [enabled: false]
    )

    group_ids
  end

  defp delete_groups!(_bridge, []), do: []

  defp delete_groups!(bridge, source_ids) do
    group_ids = group_ids_for_source_ids(bridge, source_ids)

    hidden_group_ids =
      Repo.all(
        from(g in Group,
          where: g.canonical_group_id in ^group_ids and g.enabled == false and is_nil(g.area_id),
          select: g.id
        )
      )

    all_group_ids = Enum.uniq(group_ids ++ hidden_group_ids)

    if all_group_ids != [] do
      Repo.delete_all(from(gl in GroupLight, where: gl.group_id in ^all_group_ids))
      Repo.delete_all(from(g in Group, where: g.id in ^all_group_ids))
    end

    all_group_ids
  end

  defp delete_lights!(_bridge, []), do: []

  defp delete_lights!(bridge, source_ids) do
    light_ids = light_ids_for_source_ids(bridge, source_ids)

    hidden_light_ids =
      Repo.all(
        from(l in Light,
          where: l.canonical_light_id in ^light_ids and l.enabled == false and is_nil(l.area_id),
          select: l.id
        )
      )

    all_light_ids = Enum.uniq(light_ids ++ hidden_light_ids)

    if all_light_ids != [] do
      Repo.delete_all(from(scl in SceneComponentLight, where: scl.light_id in ^all_light_ids))
      Repo.delete_all(from(gl in GroupLight, where: gl.light_id in ^all_light_ids))
      Repo.delete_all(from(l in Light, where: l.id in ^all_light_ids))
    end

    all_light_ids
  end

  defp light_ids_for_source_ids(bridge, source_ids) do
    Repo.all(
      from(l in Light,
        where: l.bridge_id == ^bridge.id and l.source_id in ^source_ids,
        select: l.id
      )
    )
  end

  defp group_ids_for_source_ids(bridge, source_ids) do
    Repo.all(
      from(g in Group,
        where: g.bridge_id == ^bridge.id and g.source_id in ^source_ids,
        select: g.id
      )
    )
  end

  defp remove_effects(kind, ids) do
    ids
    |> Enum.uniq()
    |> Enum.map(&{:remove_entity, kind, &1})
  end

  defp run_post_commit_effects(side_effects) do
    Enum.each(side_effects, fn
      {:remove_entity, :light, id} -> HomeAssistantExport.remove_light(id)
      {:remove_entity, :group, id} -> HomeAssistantExport.remove_group(id)
    end)

    if side_effects != [] do
      HomeAssistantExport.reload()
      HomeKit.reload()
    end
  end

  defp resolution_entries(plan, resolution) do
    plan
    |> Enum.reduce([], fn {source_id, entry}, acc ->
      if match?(%{}, entry) and
           (Normalize.fetch(entry, :resolution) == resolution or
              Normalize.fetch(entry, :action) == resolution) do
        normalized_source_id = Normalize.normalize_source_id(source_id)

        if is_binary(normalized_source_id) do
          [{normalized_source_id, entry} | acc]
        else
          acc
        end
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp entry_source_ids(entries), do: Enum.map(entries, fn {source_id, _entry} -> source_id end)

  defp validate_resolution_targets!(_bridge, _type, []), do: :ok

  defp validate_resolution_targets!(bridge, type, entries) do
    Enum.each(entries, fn {source_id, entry} ->
      expected_external_id = Normalize.fetch(entry, :expected_external_id)

      if not is_binary(expected_external_id) do
        Repo.rollback({:missing_expected_external_id, type, source_id})
      else
        case fetch_existing_for_resolution(bridge, type, source_id) do
          nil ->
            Repo.rollback({:stale_resolution, type, source_id})

          record ->
            if record.external_id != expected_external_id do
              Repo.rollback({:stale_resolution, type, source_id})
            end
        end
      end
    end)
  end

  defp fetch_existing_for_resolution(bridge, :light, source_id) do
    Repo.get_by(Light, bridge_id: bridge.id, source_id: source_id)
  end

  defp fetch_existing_for_resolution(bridge, :group, source_id) do
    Repo.get_by(Group, bridge_id: bridge.id, source_id: source_id)
  end

  defp selected?(plan, source_id) when is_binary(source_id) do
    case Normalize.fetch(plan, source_id) do
      false -> false
      %{} = entry -> selected_entry?(entry)
      nil -> false
      _ -> true
    end
  end

  defp selected?(_plan, _source_id), do: false

  defp hidden_duplicate_resolution?(plan, source_id) do
    if is_binary(source_id) do
      case Normalize.fetch(plan, source_id) do
        %{} = entry ->
          Normalize.fetch(entry, :resolution) == "import_hidden_duplicate" or
            Normalize.fetch(entry, :action) == "import_hidden_duplicate"

        _ ->
          false
      end
    else
      false
    end
  end

  defp import_real_resolution?(plan, source_id) do
    if is_binary(source_id) do
      case Normalize.fetch(plan, source_id) do
        %{} = entry ->
          Normalize.fetch(entry, :resolution) == "import_real" or
            Normalize.fetch(entry, :action) == "import_real"

        _ ->
          false
      end
    else
      false
    end
  end

  defp selected_entry?(entry) do
    resolution = Normalize.fetch(entry, :resolution) || Normalize.fetch(entry, :action)

    cond do
      resolution in ["delete", "skip", "do_not_import"] -> false
      resolution in ["import", "import_real", "import_hidden_duplicate"] -> true
      Map.has_key?(entry, "selected") -> entry["selected"] != false
      Map.has_key?(entry, :selected) -> entry[:selected] != false
      true -> true
    end
  end

  defp source_id(entity),
    do: entity |> Normalize.fetch(:source_id) |> Normalize.normalize_source_id()

  defp area_source_id(entity),
    do: entity |> Normalize.fetch(:area_source_id) |> Normalize.normalize_source_id()
end
