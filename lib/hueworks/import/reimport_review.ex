defmodule Hueworks.Import.ReimportReview do
  @moduledoc false

  alias Hueworks.Import.{EntityAttrs, EntityMatch, Normalize, NormalizeJson, ReviewPlan}
  alias Hueworks.Util

  @bridge_fields [
    {:name, "Bridge name"},
    {:source_id, "Source ID"},
    {:external_id, "Stable identifier"},
    {:supports_color, "Color support"},
    {:supports_temp, "Temperature support"},
    {:reported_min_kelvin, "Minimum Kelvin"},
    {:reported_max_kelvin, "Maximum Kelvin"},
    {:metadata, "Bridge metadata"}
  ]

  def build(bridge, normalized_import, reimport, plan, current_lights, current_groups, areas) do
    incoming_lights = normalized_entries(normalized_import, :lights)
    incoming_groups = normalized_entries(normalized_import, :groups)
    statuses = reimport.statuses

    light_items =
      build_items(
        bridge,
        :light,
        incoming_lights,
        current_lights,
        Normalize.fetch(statuses, :lights) || %{},
        plan,
        normalized_import,
        areas
      )

    group_items =
      build_items(
        bridge,
        :group,
        incoming_groups,
        current_groups,
        Normalize.fetch(statuses, :groups) || %{},
        plan,
        normalized_import,
        areas
      )

    items = light_items ++ group_items

    removed =
      items
      |> Enum.filter(&(&1.status == :missing and not &1.hidden_duplicate?))
      |> group_by_area(:current_area)

    existing_items = Enum.filter(items, &(&1.status == :existing))

    existing =
      existing_items
      |> group_by_area(:current_area)
      |> Enum.map(fn area_group ->
        area_items = area_group.items

        Map.merge(area_group, %{
          automatic_updates: Enum.filter(area_items, &(&1.changes != [])),
          membership_warnings: Enum.filter(area_items, &is_map(&1.membership_warning)),
          unchanged:
            Enum.filter(area_items, &(&1.changes == [] and is_nil(&1.membership_warning)))
        })
      end)

    new =
      items
      |> Enum.filter(&(&1.status in [:new, :duplicate, :ambiguous_identity]))
      |> group_by_area(:bridge_area)

    summary = %{
      removed: count_grouped(removed),
      existing: length(existing_items),
      new: count_grouped(new),
      automatic_updates: Enum.count(existing_items, &(&1.changes != [])),
      unchanged:
        Enum.count(existing_items, &(&1.changes == [] and is_nil(&1.membership_warning))),
      membership_warnings: Enum.count(existing_items, &is_map(&1.membership_warning)),
      hidden_duplicates: Enum.count(items, &(&1.status == :duplicate))
    }

    %{
      removed: removed,
      existing: existing,
      new: new,
      summary: summary,
      transaction: transaction_summary(items, plan, summary)
    }
  end

  defp build_items(
         bridge,
         type,
         incoming,
         current,
         statuses,
         plan,
         normalized_import,
         areas
       ) do
    incoming_by_source = Map.new(incoming, &{source_id(&1), &1})
    bridge_areas = bridge_area_names(normalized_import)

    status_items =
      Enum.map(statuses, fn {source_id, status} ->
        incoming_entry = Map.get(incoming_by_source, source_id)
        current_entry = match_current(current, incoming_entry, source_id, status, type)

        item = %{
          type: type,
          type_label: if(type == :light, do: "Light", else: "Group"),
          source_id: source_id,
          status: status,
          incoming: incoming_entry,
          current: current_entry,
          name: display_name(current_entry, incoming_entry, type),
          bridge_name: incoming_name(incoming_entry),
          current_area: current_area_name(current_entry),
          bridge_area: bridge_area_name(incoming_entry, bridge_areas),
          hidden_duplicate?: hidden_duplicate?(current_entry, type),
          resolution: ReviewPlan.entity_resolution(plan, plural(type), source_id),
          selected?: ReviewPlan.selected?(plan, plural(type), source_id),
          target_area_id: ReviewPlan.entity_target_area(plan, plural(type), source_id),
          changes: bridge_changes(bridge, current_entry, incoming_entry, type),
          membership_warning: nil,
          dependencies: []
        }

        maybe_add_membership(item, normalized_import, current, plan, areas)
      end)

    missing_statuses = MapSet.new(Enum.map(status_items, & &1.source_id))

    current
    |> Enum.reject(&MapSet.member?(missing_statuses, &1.source_id))
    |> Enum.map(fn record ->
      %{
        type: type,
        type_label: if(type == :light, do: "Light", else: "Group"),
        source_id: record.source_id,
        status: :missing,
        incoming: nil,
        current: record,
        name: Util.display_name(record),
        bridge_name: nil,
        current_area: current_area_name(record),
        bridge_area: "Unassigned",
        hidden_duplicate?: hidden_duplicate?(record, type),
        resolution: ReviewPlan.entity_resolution(plan, plural(type), record.source_id),
        selected?: false,
        target_area_id: nil,
        changes: [],
        membership_warning: nil,
        dependencies: []
      }
    end)
    |> Kernel.++(status_items)
  end

  defp match_current(current, incoming, source_id, status, type)
       when status in [:existing, :ambiguous_identity] and is_map(incoming) do
    case EntityMatch.match_existing(current, incoming, type) do
      record when is_map(record) -> record
      _ -> Enum.find(current, &(&1.source_id == source_id))
    end
  end

  defp match_current(current, _incoming, source_id, :missing, _type),
    do: Enum.find(current, &(&1.source_id == source_id))

  defp match_current(_current, _incoming, _source_id, _status, _type), do: nil

  defp bridge_changes(_bridge, nil, _incoming, _type), do: []
  defp bridge_changes(_bridge, _current, nil, _type), do: []

  defp bridge_changes(bridge, current, incoming, type) do
    attrs =
      case type do
        :light -> EntityAttrs.light_attrs(bridge, incoming)
        :group -> EntityAttrs.group_attrs(bridge, incoming)
      end

    Enum.flat_map(@bridge_fields, fn {field, label} ->
      current_value = Map.get(current, field)
      bridge_value = Map.get(attrs, field)

      if comparable_value(current_value) == comparable_value(bridge_value) do
        []
      else
        [%{field: field, label: label, current: current_value, bridge: bridge_value}]
      end
    end)
  end

  defp maybe_add_membership(
         %{type: :group, status: :existing} = item,
         normalized,
         lights,
         plan,
         _areas
       ) do
    memberships =
      normalized
      |> Normalize.fetch(:memberships)
      |> Kernel.||(%{})
      |> Normalize.fetch(:group_lights)
      |> Kernel.||([])

    upstream_members =
      memberships
      |> Enum.filter(&(source_id_for(&1, :group_source_id) == item.source_id))
      |> Enum.map(&source_id_for(&1, :light_source_id))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    explicit_empty? = upstream_members == [] and upstream_members_empty?(item.incoming)

    if upstream_members != [] or explicit_empty? do
      unresolved =
        Enum.reject(upstream_members, fn member_source_id ->
          Enum.any?(lights, &(&1.source_id == member_source_id)) or
            ReviewPlan.selected?(plan, :lights, member_source_id)
        end)

      current_members =
        item.current
        |> Map.get(:lights, [])
        |> Enum.map(& &1.source_id)
        |> Enum.sort()

      incoming_members = Enum.sort(upstream_members)

      cond do
        unresolved != [] ->
          %{item | membership_warning: %{unresolved_source_ids: unresolved}}

        current_members != incoming_members ->
          change = %{
            field: :membership,
            label: "Group membership",
            current: current_members,
            bridge: incoming_members
          }

          %{item | changes: item.changes ++ [change]}

        true ->
          item
      end
    else
      item
    end
  end

  defp maybe_add_membership(item, _normalized, _lights, _plan, _areas), do: item

  defp upstream_members_empty?(nil), do: false

  defp upstream_members_empty?(entry) do
    entry
    |> Normalize.fetch(:metadata)
    |> Kernel.||(%{})
    |> Normalize.fetch(:members)
    |> case do
      [] -> true
      _ -> false
    end
  end

  defp group_by_area(items, field) do
    items
    |> Enum.group_by(&Map.fetch!(&1, field))
    |> Enum.map(fn {area, area_items} ->
      %{area: area, items: Enum.sort_by(area_items, &{&1.type_label, &1.name})}
    end)
    |> Enum.sort_by(fn %{area: area} -> if area == "Unassigned", do: "~~~", else: area end)
  end

  defp transaction_summary(items, plan, summary) do
    import_count =
      Enum.count(items, fn item ->
        item.status in [:new, :duplicate] and
          ReviewPlan.selected?(plan, plural(item.type), item.source_id)
      end)

    disable_count = Enum.count(items, &(&1.status == :missing and &1.resolution == "disable"))
    delete_count = Enum.count(items, &(&1.status == :missing and &1.resolution == "delete"))

    %{
      import: import_count,
      disable: disable_count,
      delete: delete_count,
      automatic_updates: summary.automatic_updates,
      membership_warnings: summary.membership_warnings
    }
  end

  defp bridge_area_names(normalized) do
    normalized
    |> normalized_entries(:areas)
    |> Map.new(fn area -> {source_id(area), Normalize.fetch(area, :name) || "Unassigned"} end)
  end

  defp bridge_area_name(nil, _area_names), do: "Unassigned"

  defp bridge_area_name(entry, area_names) do
    entry
    |> Normalize.fetch(:area_source_id)
    |> Normalize.normalize_source_id()
    |> then(&Map.get(area_names, &1, "Unassigned"))
  end

  defp current_area_name(%{area: area}) when is_map(area), do: Util.display_name(area)
  defp current_area_name(_record), do: "Unassigned"

  defp display_name(record, _incoming, _type) when is_map(record), do: Util.display_name(record)
  defp display_name(_record, incoming, type), do: incoming_name(incoming) || default_name(type)

  defp incoming_name(nil), do: nil
  defp incoming_name(entry), do: Normalize.fetch(entry, :name)

  defp default_name(:light), do: "Light"
  defp default_name(:group), do: "Group"

  defp hidden_duplicate?(nil, _type), do: false

  defp hidden_duplicate?(record, :light),
    do: is_integer(record.canonical_light_id) and !record.enabled

  defp hidden_duplicate?(record, :group),
    do: is_integer(record.canonical_group_id) and !record.enabled

  defp count_grouped(groups), do: Enum.sum(Enum.map(groups, &length(&1.items)))

  defp comparable_value(value) when is_map(value), do: NormalizeJson.to_map(value)
  defp comparable_value(value), do: value

  defp normalized_entries(normalized, key), do: Normalize.fetch(normalized, key) || []

  defp source_id(entry),
    do: entry |> Normalize.fetch(:source_id) |> Normalize.normalize_source_id()

  defp source_id_for(entry, key),
    do: entry |> Normalize.fetch(key) |> Normalize.normalize_source_id()

  defp plural(:light), do: :lights
  defp plural(:group), do: :groups
end
