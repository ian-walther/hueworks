defmodule Hueworks.Import.ReimportPlan do
  @moduledoc false

  alias Hueworks.Import.{Identifiers, Normalize, NormalizeJson}
  alias Hueworks.Util

  def build(normalized_import, normalized_db, rooms) do
    import_rooms = Normalize.fetch(normalized_import, :rooms) || []
    import_lights = Normalize.fetch(normalized_import, :lights) || []
    import_groups = Normalize.fetch(normalized_import, :groups) || []

    db_lights = Normalize.fetch(normalized_db, :lights) || []
    db_groups = Normalize.fetch(normalized_db, :groups) || []

    existing_light_ids = external_id_set(db_lights, :light)
    existing_group_ids = external_id_set(db_groups, :group)

    missing_lights = missing_entries(db_lights, external_id_set(import_lights, :light), :light)
    missing_groups = missing_entries(db_groups, external_id_set(import_groups, :group), :group)

    statuses = %{
      rooms: %{},
      lights: status_map(import_lights, missing_lights, existing_light_ids, :light),
      groups: status_map(import_groups, missing_groups, existing_group_ids, :group)
    }

    plan = %{
      rooms: build_room_plan(import_rooms, rooms),
      lights: build_selection(import_lights, existing_light_ids, :light),
      groups: build_selection(import_groups, existing_group_ids, :group)
    }

    merged_normalized =
      normalized_import
      |> Map.put(:lights, import_lights ++ missing_lights)
      |> Map.put(:groups, import_groups ++ missing_groups)

    %{plan: plan, normalized: NormalizeJson.to_map(merged_normalized), statuses: statuses}
  end

  def deletions(plan, normalized_import, normalized_db) do
    import_lights = Normalize.fetch(normalized_import, :lights) || []
    import_groups = Normalize.fetch(normalized_import, :groups) || []
    db_lights = Normalize.fetch(normalized_db, :lights) || []
    db_groups = Normalize.fetch(normalized_db, :groups) || []

    import_light_by_external = import_external_id_map(import_lights, :light)
    import_group_by_external = import_external_id_map(import_groups, :group)

    delete_lights =
      db_lights
      |> Enum.reduce([], fn entry, acc ->
        external_id = external_id(entry, :light)

        case external_id do
          nil ->
            acc

          _ ->
            case Map.get(import_light_by_external, external_id) do
              nil ->
                [external_id | acc]

              source_id ->
                if selected?(plan, :lights, source_id) do
                  acc
                else
                  [external_id | acc]
                end
            end
        end
      end)
      |> Enum.uniq()

    delete_groups =
      db_groups
      |> Enum.reduce([], fn entry, acc ->
        external_id = external_id(entry, :group)

        case external_id do
          nil ->
            acc

          _ ->
            case Map.get(import_group_by_external, external_id) do
              nil ->
                [external_id | acc]

              source_id ->
                if selected?(plan, :groups, source_id) do
                  acc
                else
                  [external_id | acc]
                end
            end
        end
      end)
      |> Enum.uniq()

    %{lights: delete_lights, groups: delete_groups}
  end

  defp build_room_plan(import_rooms, rooms) do
    room_lookup =
      Enum.reduce(rooms, %{}, fn room, acc ->
        name = Util.normalize_room_name(room.name)
        Map.put(acc, name, room.id)
      end)

    Enum.reduce(import_rooms, %{}, fn room, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(room, :source_id))
      name = Normalize.fetch(room, :name) || "Room"
      normalized_name = Normalize.fetch(room, :normalized_name) || Util.normalize_room_name(name)

      if is_binary(source_id) do
        case Map.get(room_lookup, normalized_name) do
          nil ->
            Map.put(acc, source_id, %{
              "action" => "create",
              "target_room_id" => nil,
              "name" => name
            })

          room_id ->
            Map.put(acc, source_id, %{
              "action" => "merge",
              "target_room_id" => Integer.to_string(room_id),
              "name" => name
            })
        end
      else
        acc
      end
    end)
  end

  defp build_selection(import_entries, import_ids, type) do
    import_entries
    |> Enum.reduce(%{}, fn entry, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
      external_id = external_id(entry, type)

      if is_binary(source_id) and is_binary(external_id) do
        Map.put(acc, source_id, MapSet.member?(import_ids, external_id))
      else
        acc
      end
    end)
  end

  defp status_map(import_entries, missing_entries, import_ids, type) do
    import_entries
    |> Enum.reduce(%{}, fn entry, acc ->
      source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
      external_id = external_id(entry, type)

      status =
        if is_binary(external_id) and MapSet.member?(import_ids, external_id) do
          :existing
        else
          :new
        end

      if is_binary(source_id), do: Map.put(acc, source_id, status), else: acc
    end)
    |> then(fn acc ->
      Enum.reduce(missing_entries, acc, fn entry, inner ->
        source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))
        if is_binary(source_id), do: Map.put(inner, source_id, :missing), else: inner
      end)
    end)
  end

  defp missing_entries(db_entries, import_ids, type) do
    Enum.filter(db_entries, fn entry ->
      external_id = external_id(entry, type)
      is_binary(external_id) and not MapSet.member?(import_ids, external_id)
    end)
  end

  defp import_external_id_map(import_entries, type) do
    Enum.reduce(import_entries, %{}, fn entry, acc ->
      external_id = external_id(entry, type)
      source_id = Normalize.normalize_source_id(Normalize.fetch(entry, :source_id))

      if is_binary(external_id) and is_binary(source_id) do
        Map.put(acc, external_id, source_id)
      else
        acc
      end
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

  defp selected?(plan, key, source_id) do
    map = Normalize.fetch(plan, key) || %{}
    case Map.get(map, source_id, true) do
      false -> false
      _ -> true
    end
  end
end
