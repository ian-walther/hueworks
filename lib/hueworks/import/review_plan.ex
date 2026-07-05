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

  def put_room(plan, source_id, attrs) do
    source_id = Normalize.normalize_source_id(source_id)
    plan = plan || %{}
    rooms = Normalize.fetch(plan, :rooms) || %{}

    if is_binary(source_id) do
      current = Map.get(rooms, source_id, %{})
      updated = Map.merge(current, attrs)
      Map.put(plan, :rooms, Map.put(rooms, source_id, updated))
    else
      plan
    end
  end

  def put_entity_room(plan, type, source_id, target_room_id) do
    key = entity_key(type)
    source_id = Normalize.normalize_source_id(source_id)
    plan = plan || %{}
    map = Normalize.fetch(plan, key) || %{}

    if is_binary(source_id) do
      current = Map.get(map, source_id, true)

      updated =
        current
        |> selection_map()
        |> Map.put("target_room_id", blank_to_nil(target_room_id))

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

  def entity_target_room(plan, key, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    map = Normalize.fetch(plan, key) || %{}

    case source_id do
      nil ->
        nil

      _ ->
        map
        |> Map.get(source_id, %{})
        |> Normalize.fetch(:target_room_id)
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

  def room_action(plan, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    rooms = Normalize.fetch(plan, :rooms) || %{}

    case source_id do
      nil ->
        "create"

      _ ->
        rooms
        |> Map.get(source_id, %{})
        |> Normalize.fetch(:action)
        |> case do
          nil -> "create"
          value -> value
        end
    end
  end

  def room_merge_target(plan, source_id) do
    source_id = Normalize.normalize_source_id(source_id)
    rooms = Normalize.fetch(plan, :rooms) || %{}

    case source_id do
      nil ->
        nil

      _ ->
        rooms
        |> Map.get(source_id, %{})
        |> Normalize.fetch(:target_room_id)
        |> Normalize.normalize_source_id()
    end
  end

  def apply_bulk_toggle(plan, normalized, rooms, value) do
    rooms_entries = normalized_entries(normalized, :rooms)
    lights = normalized_entries(normalized, :lights)
    groups = normalized_entries(normalized, :groups)
    room_ids = entity_ids(rooms_entries)
    light_ids = entity_ids(lights)
    group_ids = entity_ids(groups)

    action = if value == "check", do: "check", else: "skip"
    selected = value == "check"

    plan
    |> put_room_actions(room_ids, action, normalized, rooms)
    |> put_selection(:lights, light_ids, selected)
    |> put_selection(:groups, group_ids, selected)
  end

  def apply_room_toggle(plan, normalized, rooms, room_id, value) do
    selected = value == "check"
    action = if selected, do: "check", else: "skip"

    light_ids = room_entity_ids(normalized, room_id, :lights)
    group_ids = room_entity_ids(normalized, room_id, :groups)
    room_ids = room_entity_ids(normalized, room_id, :rooms)

    plan
    |> put_room_actions(room_ids, action, normalized, rooms)
    |> put_selection(:lights, light_ids, selected)
    |> put_selection(:groups, group_ids, selected)
  end

  def apply_room_section_toggle(plan, normalized, room_id, section, value) do
    selected = value == "check"
    section_key = if section == "groups", do: :groups, else: :lights

    ids =
      if room_id == "unassigned" do
        unassigned_entity_ids(normalized, section_key)
      else
        room_entity_ids(normalized, room_id, section_key)
      end

    put_selection(plan, section_key, ids, selected)
  end

  def apply_bulk_resolution(plan, statuses, status, resolution) do
    status = normalize_status(status)

    plan
    |> put_bulk_resolution(:lights, Normalize.fetch(statuses, :lights) || %{}, status, resolution)
    |> put_bulk_resolution(:groups, Normalize.fetch(statuses, :groups) || %{}, status, resolution)
  end

  def apply_room_merge_defaults(plan, normalized, rooms) do
    room_entries = normalized_entries(normalized, :rooms)
    room_ids = entity_ids(room_entries)
    put_room_actions(plan, room_ids, "check", normalized, rooms)
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

  defp put_room_actions(plan, room_ids, action, normalized, rooms) do
    plan = plan || %{}
    plan_rooms = Normalize.fetch(plan, :rooms) || %{}

    updated =
      Enum.reduce(room_ids, plan_rooms, fn room_id, acc ->
        current = Map.get(acc, room_id, %{})
        new_attrs = room_action_for(room_id, action, normalized, rooms)
        Map.put(acc, room_id, Map.merge(current, new_attrs))
      end)

    Map.put(plan, :rooms, updated)
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

  defp room_action_for(_room_id, "skip", _normalized, _rooms) do
    %{"action" => "skip", "target_room_id" => nil}
  end

  defp room_action_for(room_id, _action, normalized, rooms) do
    room_entries = normalized_entries(normalized, :rooms)
    source_id = Normalize.normalize_source_id(room_id)

    room =
      Enum.find(room_entries, fn entry ->
        Normalize.normalize_source_id(Normalize.fetch(entry, :source_id)) == source_id
      end)

    case matching_room_id(room, rooms) do
      nil ->
        %{"action" => "create", "target_room_id" => nil}

      target_id ->
        %{"action" => "merge", "target_room_id" => Integer.to_string(target_id)}
    end
  end

  defp matching_room_id(nil, _rooms), do: nil

  defp matching_room_id(room, rooms) do
    name = Normalize.fetch(room, :name) || "Room"
    normalized_name = Normalize.fetch(room, :normalized_name) || Util.normalize_room_name(name)

    rooms
    |> Enum.find_value(fn existing ->
      if Util.normalize_room_name(existing.name) == normalized_name do
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

  defp room_entity_ids(_normalized, room_id, :rooms) do
    case Normalize.normalize_source_id(room_id) do
      nil -> []
      id -> [id]
    end
  end

  defp room_entity_ids(normalized, room_id, type) when type in [:lights, :groups] do
    room_key = Normalize.normalize_source_id(room_id)
    entries = normalized_entries(normalized, type)

    if is_binary(room_key) do
      entries
      |> Enum.reduce([], fn entry, acc ->
        entry_room =
          entry
          |> Normalize.fetch(:room_source_id)
          |> Normalize.normalize_source_id()

        if entry_room == room_key do
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
    room_keys =
      normalized_entries(normalized, :rooms)
      |> Enum.map(fn room ->
        room
        |> Normalize.fetch(:source_id)
        |> Normalize.normalize_source_id()
      end)
      |> Enum.filter(&is_binary/1)

    normalized_entries(normalized, type)
    |> Enum.reduce([], fn entry, acc ->
      room_key =
        entry
        |> Normalize.fetch(:room_source_id)
        |> Normalize.normalize_source_id()

      if not is_binary(room_key) or not Enum.member?(room_keys, room_key) do
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
