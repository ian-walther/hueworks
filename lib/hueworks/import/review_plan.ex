defmodule Hueworks.Import.ReviewPlan do
  @moduledoc false

  alias Hueworks.Import.Normalize
  alias Hueworks.Util

  def toggle_entity(plan, type, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    plan = plan || %{}
    map = Normalize.fetch(plan, type) || %{}

    if is_binary(source_id) do
      current = Map.get(map, source_id, true)
      Map.put(plan, type, Map.put(map, source_id, toggle_selection(current)))
    else
      plan
    end
  end

  def put_area(plan, source_id, attrs) do
    source_id = Normalize.normalize_source_id(source_id)
    plan = plan || %{}
    areas = Normalize.fetch(plan, :areas) || %{}

    if is_binary(source_id) do
      current = Map.get(areas, source_id, %{})
      updated = Map.merge(current, attrs)
      Map.put(plan, :areas, Map.put(areas, source_id, updated))
    else
      plan
    end
  end

  def put_entity_area(plan, type, source_id, target_area_id) do
    key = entity_key(type)
    source_id = Normalize.normalize_source_id(source_id)
    plan = plan || %{}
    map = Normalize.fetch(plan, key) || %{}

    if is_binary(source_id) do
      current = Map.get(map, source_id, true)

      updated =
        current
        |> selection_map()
        |> Map.put("target_area_id", blank_to_nil(target_area_id))

      Map.put(plan, key, Map.put(map, source_id, updated))
    else
      plan
    end
  end

  def put_entity_resolution(plan, type, source_id, resolution) do
    key = entity_key(type)
    source_id = Normalize.normalize_source_id(source_id)
    plan = plan || %{}
    map = Normalize.fetch(plan, key) || %{}

    if is_binary(source_id) do
      current = Map.get(map, source_id, true)

      updated =
        current
        |> selection_map()
        |> Map.put("resolution", resolution)
        |> Map.put("selected", resolution_selected?(resolution))

      Map.put(plan, key, Map.put(map, source_id, updated))
    else
      plan
    end
  end

  def selected?(plan, key, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    map = Normalize.fetch(plan, key) || %{}

    if is_binary(source_id) do
      case Map.get(map, source_id, true) do
        false -> false
        %{} = entry -> Map.get(entry, "selected", true)
        _ -> true
      end
    else
      false
    end
  end

  def entity_target_area(plan, key, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    map = Normalize.fetch(plan, key) || %{}

    case source_id do
      nil ->
        nil

      _ ->
        map
        |> Map.get(source_id, %{})
        |> Normalize.fetch(:target_area_id)
        |> Normalize.normalize_source_id()
    end
  end

  def entity_resolution(plan, key, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    map = Normalize.fetch(plan, key) || %{}

    case source_id do
      nil ->
        nil

      _ ->
        map
        |> Map.get(source_id, %{})
        |> Normalize.fetch(:resolution)
    end
  end

  def area_action(plan, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    areas = Normalize.fetch(plan, :areas) || %{}

    case source_id do
      nil ->
        "create"

      _ ->
        areas
        |> Map.get(source_id, %{})
        |> Normalize.fetch(:action)
        |> case do
          nil -> "create"
          value -> value
        end
    end
  end

  def area_merge_target(plan, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    areas = Normalize.fetch(plan, :areas) || %{}

    case source_id do
      nil ->
        nil

      _ ->
        areas
        |> Map.get(source_id, %{})
        |> Normalize.fetch(:target_area_id)
        |> Normalize.normalize_source_id()
    end
  end

  def apply_bulk_toggle(plan, normalized, areas, value) do
    areas_entries = normalized_entries(normalized, :areas)
    lights = normalized_entries(normalized, :lights)
    groups = normalized_entries(normalized, :groups)
    area_ids = entity_ids(areas_entries)
    light_ids = entity_ids(lights)
    group_ids = entity_ids(groups)

    action = if value == "check", do: "check", else: "skip"
    selected = value == "check"

    plan
    |> put_area_actions(area_ids, action, normalized, areas)
    |> put_selection(:lights, light_ids, selected)
    |> put_selection(:groups, group_ids, selected)
  end

  def apply_area_toggle(plan, normalized, areas, area_id, value) do
    selected = value == "check"
    action = if selected, do: "check", else: "skip"

    light_ids = area_entity_ids(normalized, area_id, :lights)
    group_ids = area_entity_ids(normalized, area_id, :groups)
    area_ids = area_entity_ids(normalized, area_id, :areas)

    plan
    |> put_area_actions(area_ids, action, normalized, areas)
    |> put_selection(:lights, light_ids, selected)
    |> put_selection(:groups, group_ids, selected)
  end

  def apply_area_section_toggle(plan, normalized, area_id, section, value) do
    selected = value == "check"
    section_key = if section == "groups", do: :groups, else: :lights

    ids =
      if area_id == "unassigned" do
        unassigned_entity_ids(normalized, section_key)
      else
        area_entity_ids(normalized, area_id, section_key)
      end

    put_selection(plan, section_key, ids, selected)
  end

  def apply_bulk_resolution(plan, statuses, status, resolution) do
    status = normalize_status(status)

    plan
    |> put_bulk_resolution(:lights, Normalize.fetch(statuses, :lights) || %{}, status, resolution)
    |> put_bulk_resolution(:groups, Normalize.fetch(statuses, :groups) || %{}, status, resolution)
  end

  def apply_area_merge_defaults(plan, normalized, areas) do
    area_entries = normalized_entries(normalized, :areas)
    area_ids = entity_ids(area_entries)
    put_area_actions(plan, area_ids, "check", normalized, areas)
  end

  def destructive_resolutions(plan) do
    [
      {:lights, :light},
      {:groups, :group}
    ]
    |> Enum.flat_map(fn {key, type} ->
      plan
      |> Normalize.fetch(key)
      |> Kernel.||(%{})
      |> Enum.flat_map(fn {source_id, entry} ->
        destructive_resolution(source_id, entry, type)
      end)
    end)
  end

  defp destructive_resolution(source_id, entry, type) when is_map(entry) do
    action = Normalize.fetch(entry, :resolution) || Normalize.fetch(entry, :action)
    source_id = Normalize.normalize_source_id(source_id)

    if action in ["delete", "disable"] and is_binary(source_id) do
      [
        %{
          type: type,
          source_id: source_id,
          action: String.to_existing_atom(action),
          expected_external_id: Normalize.fetch(entry, :expected_external_id)
        }
      ]
    else
      []
    end
  end

  defp destructive_resolution(_source_id, _entry, _type), do: []

  defp normalized_entries(normalized, key) do
    Normalize.fetch(normalized, key) || []
  end

  defp put_bulk_resolution(plan, key, statuses, status, resolution) do
    ids =
      statuses
      |> Enum.filter(fn {_source_id, entity_status} -> entity_status == status end)
      |> Enum.map(fn {source_id, _entity_status} -> source_id end)

    Enum.reduce(ids, plan || %{}, fn source_id, acc ->
      put_entity_resolution(acc, Atom.to_string(key), source_id, resolution)
    end)
  end

  defp put_area_actions(plan, area_ids, action, normalized, areas) do
    plan = plan || %{}
    plan_areas = Normalize.fetch(plan, :areas) || %{}

    updated =
      Enum.reduce(area_ids, plan_areas, fn area_id, acc ->
        current = Map.get(acc, area_id, %{})
        new_attrs = area_action_for(area_id, action, normalized, areas)
        Map.put(acc, area_id, Map.merge(current, new_attrs))
      end)

    Map.put(plan, :areas, updated)
  end

  defp put_selection(plan, key, ids, selected) do
    plan = plan || %{}
    map = Normalize.fetch(plan, key) || %{}

    updated =
      Enum.reduce(ids, map, fn id, acc ->
        Map.put(acc, id, merge_selection_value(Map.get(acc, id, true), selected))
      end)

    Map.put(plan, key, updated)
  end

  defp area_action_for(_area_id, "skip", _normalized, _areas) do
    %{"action" => "skip", "target_area_id" => nil}
  end

  defp area_action_for(area_id, _action, normalized, areas) do
    area_entries = normalized_entries(normalized, :areas)
    source_id = Normalize.normalize_source_id(area_id)

    area =
      Enum.find(area_entries, fn entry ->
        Normalize.normalize_source_id(Normalize.fetch(entry, :source_id)) == source_id
      end)

    case matching_area_id(area, areas) do
      nil ->
        %{"action" => "create", "target_area_id" => nil}

      target_id ->
        %{"action" => "merge", "target_area_id" => Integer.to_string(target_id)}
    end
  end

  defp matching_area_id(nil, _areas), do: nil

  defp matching_area_id(area, areas) do
    name = Normalize.fetch(area, :name) || "Area"
    normalized_name = Normalize.fetch(area, :normalized_name) || Util.normalize_area_name(name)

    areas
    |> Enum.find_value(fn existing ->
      if Util.normalize_area_name(existing.name) == normalized_name do
        existing.id
      end
    end)
  end

  defp entity_ids(entries) do
    entries
    |> Enum.map(fn entry ->
      entry
      |> Normalize.fetch(:source_id)
      |> Normalize.normalize_source_id()
    end)
    |> Enum.filter(&is_binary/1)
  end

  defp area_entity_ids(_normalized, area_id, :areas) do
    case Normalize.normalize_source_id(area_id) do
      nil -> []
      id -> [id]
    end
  end

  defp area_entity_ids(normalized, area_id, type) when type in [:lights, :groups] do
    area_key = Normalize.normalize_source_id(area_id)
    entries = normalized_entries(normalized, type)

    if is_binary(area_key) do
      entries
      |> Enum.reduce([], fn entry, acc ->
        entry_area =
          entry
          |> Normalize.fetch(:area_source_id)
          |> Normalize.normalize_source_id()

        if entry_area == area_key do
          case Normalize.normalize_source_id(Normalize.fetch(entry, :source_id)) do
            nil -> acc
            id -> [id | acc]
          end
        else
          acc
        end
      end)
      |> Enum.reverse()
    else
      []
    end
  end

  defp unassigned_entity_ids(normalized, type) when type in [:lights, :groups] do
    area_keys =
      normalized_entries(normalized, :areas)
      |> Enum.map(fn area ->
        area
        |> Normalize.fetch(:source_id)
        |> Normalize.normalize_source_id()
      end)
      |> Enum.filter(&is_binary/1)

    normalized_entries(normalized, type)
    |> Enum.reduce([], fn entry, acc ->
      area_key =
        entry
        |> Normalize.fetch(:area_source_id)
        |> Normalize.normalize_source_id()

      if not is_binary(area_key) or not Enum.member?(area_keys, area_key) do
        case Normalize.normalize_source_id(Normalize.fetch(entry, :source_id)) do
          nil -> acc
          id -> [id | acc]
        end
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp entity_key("groups"), do: :groups
  defp entity_key(:groups), do: :groups
  defp entity_key(_type), do: :lights

  defp normalize_status("new"), do: :new
  defp normalize_status("missing"), do: :missing
  defp normalize_status("duplicate"), do: :duplicate
  defp normalize_status("ambiguous_identity"), do: :ambiguous_identity
  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status(_status), do: nil

  defp toggle_selection(false), do: true
  defp toggle_selection(true), do: false

  defp toggle_selection(map) when is_map(map),
    do: Map.put(map, "selected", !Map.get(map, "selected", true))

  defp toggle_selection(_value), do: false

  defp merge_selection_value(current, selected) when is_map(current) do
    Map.put(current, "selected", selected)
  end

  defp merge_selection_value(_current, selected), do: selected

  defp selection_map(map) when is_map(map), do: map
  defp selection_map(_value), do: %{"selected" => true}

  defp resolution_selected?(resolution),
    do: resolution in ["import", "import_real", "import_hidden_duplicate"]

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
