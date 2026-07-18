defmodule Hueworks.Import.ReimportPlan do
  @moduledoc false

  alias Hueworks.Import.{Duplicates, Identifiers, Normalize, NormalizeJson, SpaceMappings}
  alias Hueworks.Util

  def build(normalized_import, normalized_db, areas) do
    import_areas = Normalize.fetch(normalized_import, :areas) || []

    import_lights =
      normalized_import
      |> Normalize.fetch(:lights)
      |> Kernel.||([])
      |> Duplicates.reject_hueworks_exported()

    import_groups =
      normalized_import
      |> Normalize.fetch(:groups)
      |> Kernel.||([])
      |> Duplicates.reject_hueworks_exported()

    db_lights = Normalize.fetch(normalized_db, :lights) || []
    db_groups = Normalize.fetch(normalized_db, :groups) || []

    existing_light_ids = external_id_set(db_lights, :light)
    existing_group_ids = external_id_set(db_groups, :group)
    duplicate_light_targets = Duplicates.light_targets(import_lights)

    light_canonical_targets =
      duplicate_light_targets
      |> Map.merge(
        normalized_db
        |> bridge_id()
        |> Duplicates.existing_light_canonical_targets(import_lights)
      )

    duplicate_group_targets = duplicate_group_targets(import_groups, light_canonical_targets)

    ambiguous_light_ids = ambiguous_source_ids(import_lights, db_lights, :light)
    ambiguous_group_ids = ambiguous_source_ids(import_groups, db_groups, :group)

    missing_lights = missing_entries(db_lights, external_id_set(import_lights, :light), :light)
    missing_groups = missing_entries(db_groups, external_id_set(import_groups, :group), :group)
    area_plan = build_area_plan(import_areas, areas)

    statuses = %{
      areas: %{},
      lights:
        status_map(
          import_lights,
          missing_lights,
          existing_light_ids,
          duplicate_light_targets,
          ambiguous_light_ids,
          :light
        ),
      groups:
        status_map(
          import_groups,
          missing_groups,
          existing_group_ids,
          duplicate_group_targets,
          ambiguous_group_ids,
          :group
        )
    }

    plan =
      %{
        areas: area_plan,
        external_space_mappings: %{},
        lights:
          build_selection(
            import_lights,
            existing_light_ids,
            duplicate_light_targets,
            ambiguous_light_ids,
            :light,
            area_plan
          )
          |> add_missing_selection(missing_lights, :light),
        groups:
          build_selection(
            import_groups,
            existing_group_ids,
            duplicate_group_targets,
            ambiguous_group_ids,
            :group,
            area_plan
          )
          |> add_missing_selection(missing_groups, :group)
      }
      |> SpaceMappings.apply_plan_defaults(normalized_import)

    merged_normalized =
      normalized_import
      |> Map.put(:lights, import_lights ++ missing_lights)
      |> Map.put(:groups, import_groups ++ missing_groups)

    %{plan: plan, normalized: NormalizeJson.to_map(merged_normalized), statuses: statuses}
  end

  defp build_area_plan(import_areas, areas) do
    area_lookup =
      Enum.reduce(areas, %{}, fn area, acc ->
        name = Util.normalize_area_name(area.name)
        Map.put(acc, name, area.id)
      end)

    Enum.reduce(import_areas, %{}, fn area, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(area, :source_id))
      name = Normalize.fetch(area, :name) || "Area"
      normalized_name = Normalize.fetch(area, :normalized_name) || Util.normalize_area_name(name)

      if is_binary(source_id) do
        case Map.get(area_lookup, normalized_name) do
          nil ->
            Map.put(acc, source_id, %{
              "action" => "skip",
              "target_area_id" => nil,
              "name" => name
            })

          area_id ->
            Map.put(acc, source_id, %{
              "action" => "merge",
              "target_area_id" => Integer.to_string(area_id),
              "name" => name
            })
        end
      else
        acc
      end
    end)
  end

  defp build_selection(
         import_entries,
         import_ids,
         duplicate_targets,
         ambiguous_ids,
         type,
         area_plan
       ) do
    import_entries
    |> Enum.reduce(%{}, fn entry, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
      external_id = external_id(entry, type)

      if is_binary(source_id) and is_binary(external_id) do
        value =
          cond do
            MapSet.member?(ambiguous_ids, source_id) ->
              %{"selected" => false, "resolution" => "keep_separate"}

            MapSet.member?(import_ids, external_id) ->
              true

            Map.has_key?(duplicate_targets, source_id) ->
              %{"selected" => true, "resolution" => "import_hidden_duplicate"}

            true ->
              new_entity_selection(entry, area_plan)
          end

        Map.put(acc, source_id, value)
      else
        acc
      end
    end)
  end

  defp new_entity_selection(entry, area_plan) do
    area_source_id =
      entry
      |> Normalize.fetch(:area_source_id)
      |> Normalize.normalize_source_id()

    target_area_id =
      area_plan
      |> Map.get(area_source_id, %{})
      |> Normalize.fetch(:target_area_id)
      |> Normalize.normalize_source_id()
      |> Kernel.||("unassigned")

    %{
      "selected" => false,
      "resolution" => "do_not_import",
      "target_area_id" => target_area_id
    }
  end

  defp add_missing_selection(selection, missing_entries, type) do
    Enum.reduce(missing_entries, selection, fn entry, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))

      if is_binary(source_id) do
        Map.put_new(acc, source_id, %{
          "selected" => false,
          "resolution" => "keep",
          "expected_external_id" => external_id(entry, type)
        })
      else
        acc
      end
    end)
  end

  defp status_map(
         import_entries,
         missing_entries,
         import_ids,
         duplicate_targets,
         ambiguous_ids,
         type
       ) do
    import_entries
    |> Enum.reduce(%{}, fn entry, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
      external_id = external_id(entry, type)

      status = import_status(source_id, external_id, import_ids, duplicate_targets, ambiguous_ids)

      if is_binary(source_id), do: Map.put(acc, source_id, status), else: acc
    end)
    |> then(fn acc ->
      Enum.reduce(missing_entries, acc, fn entry, inner ->
        source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
        if is_binary(source_id), do: Map.put_new(inner, source_id, :missing), else: inner
      end)
    end)
  end

  defp import_status(source_id, external_id, import_ids, duplicate_targets, ambiguous_ids) do
    cond do
      is_binary(source_id) and MapSet.member?(ambiguous_ids, source_id) -> :ambiguous_identity
      is_binary(external_id) and MapSet.member?(import_ids, external_id) -> :existing
      is_binary(source_id) and Map.has_key?(duplicate_targets, source_id) -> :duplicate
      true -> :new
    end
  end

  defp duplicate_group_targets(import_groups, duplicate_light_targets) do
    Enum.reduce(import_groups, %{}, fn group, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(group, :source_id))

      case Duplicates.group_target(group, duplicate_light_targets) do
        group_id when is_binary(source_id) and is_integer(group_id) ->
          Map.put(acc, source_id, group_id)

        _ ->
          acc
      end
    end)
  end

  defp missing_entries(db_entries, import_ids, type) do
    Enum.filter(db_entries, fn entry ->
      external_id = external_id(entry, type)
      is_binary(external_id) and not MapSet.member?(import_ids, external_id)
    end)
  end

  defp external_id_set(entries, type) do
    entries
    |> Enum.reduce(MapSet.new(), fn entry, acc ->
      case external_id(entry, type) do
        nil -> acc
        id -> MapSet.put(acc, id)
      end
    end)
  end

  defp external_id(entry, :light), do: Identifiers.light_external_id(entry)
  defp external_id(entry, :group), do: Identifiers.group_external_id(entry)

  defp ambiguous_source_ids(import_entries, db_entries, type) do
    import_entries
    |> Enum.reduce(MapSet.new(), fn entry, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
      external_id = external_id(entry, type)

      by_source_id =
        Enum.find(db_entries, fn db_entry ->
          Normalize.normalize_source_id(Normalize.fetch(db_entry, :source_id)) == source_id
        end)

      external_matches =
        Enum.filter(db_entries, fn db_entry ->
          is_binary(external_id) and external_id(db_entry, type) == external_id
        end)

      ambiguous? =
        cond do
          not is_binary(source_id) ->
            false

          by_source_id && Enum.any?(external_matches, &db_identity_differs?(&1, by_source_id)) ->
            true

          length(external_matches) > 1 ->
            true

          match = List.first(external_matches) ->
            by_source_id && db_identity_differs?(match, by_source_id)

          true ->
            false
        end

      if ambiguous?, do: MapSet.put(acc, source_id), else: acc
    end)
  end

  defp db_identity_differs?(left, right) do
    Normalize.normalize_source_id(Normalize.fetch(left, :source_id)) !=
      Normalize.normalize_source_id(Normalize.fetch(right, :source_id)) or
      external_identity(left) != external_identity(right)
  end

  defp external_identity(entry) do
    {
      Normalize.fetch(entry, :source),
      Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
    }
  end

  defp bridge_id(normalized_db) do
    normalized_db
    |> Normalize.fetch(:bridge)
    |> Kernel.||(%{})
    |> Normalize.fetch(:id)
    |> Util.parse_optional_integer()
  end
end
