defmodule Hueworks.Api do
  @moduledoc """
  Stable read model for the authenticated HueWorks API.

  This module intentionally composes the existing contexts and runtime state.
  It does not own a second cache, control path, or persistence model.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.Api.Control
  alias Hueworks.AppSettings
  alias Hueworks.Control.{DesiredState, State, TraceBuffer}
  alias Hueworks.Groups
  alias Hueworks.Kelvin
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Util
  alias Hueworks.Schemas.{ActiveScene, Group, GroupLight, Light, Room, Scene}

  @safe_state_keys [:power, :brightness, :kelvin, :x, :y]

  def status do
    settings = AppSettings.global_map()

    %{
      api_version: "v1",
      server_time: timestamp(DateTime.utc_now()),
      runtime: %{
        control_state_ready: process_running?(State),
        desired_state_ready: process_running?(DesiredState),
        trace_buffer_ready: process_running?(TraceBuffer)
      },
      integrations: %{
        home_assistant_export: settings.ha_export_enabled,
        homekit_scenes: settings.homekit_scenes_enabled
      },
      counts: %{
        rooms: Repo.aggregate(Room, :count),
        lights: Repo.aggregate(Light, :count),
        groups: Repo.aggregate(Group, :count),
        active_scenes: Repo.aggregate(ActiveScene, :count)
      }
    }
  end

  def rooms do
    Rooms.list_rooms_with_children()
    |> Enum.map(&room_index_projection/1)
  end

  def room(id) when is_integer(id) do
    case Repo.get(Room, id) do
      nil -> {:error, :not_found}
      room -> {:ok, room |> preload_room() |> room_projection()}
    end
  end

  def room(_id), do: {:error, :not_found}

  def light(id) when is_integer(id) do
    case Repo.get(Light, id) do
      nil -> {:error, :not_found}
      light -> {:ok, light_projection(light)}
    end
  end

  def light(_id), do: {:error, :not_found}

  def group(id) when is_integer(id) do
    case Repo.get(Group, id) do
      nil -> {:error, :not_found}
      group -> {:ok, group_projection(group)}
    end
  end

  def group(_id), do: {:error, :not_found}

  @doc """
  Searches lights and groups by their bridge and display names.

  The result deliberately includes disabled and canonical rows so callers can
  recognize ambiguity instead of treating a filtered result as unambiguous.
  `exact_controllable_match_count` is the safe precondition for a name-based
  control request: it must be exactly one.
  """
  def search_entities(query, filters \\ [])

  def search_entities(query, filters) when is_binary(query) and is_list(filters) do
    normalized_query = normalize_search_value(query)
    kind = Keyword.get(filters, :kind)
    room_id = Keyword.get(filters, :room_id)
    limit = normalize_search_limit(Keyword.get(filters, :limit))

    results =
      entity_search_candidates(kind)
      |> Enum.map(&entity_search_projection(&1, normalized_query))
      |> Enum.filter(&(&1.match != nil))
      |> maybe_filter_by_room(room_id)
      |> Enum.sort_by(&entity_search_sort_key/1)

    %{
      query: normalized_query,
      exact_match_count: Enum.count(results, &(&1.match == "exact")),
      exact_controllable_match_count:
        Enum.count(results, &(&1.match == "exact" and &1.controllable)),
      results: Enum.take(results, limit)
    }
  end

  def search_entities(_query, _filters),
    do: %{query: "", exact_match_count: 0, exact_controllable_match_count: 0, results: []}

  def debug_room(id) do
    with {:ok, room} <- room(id) do
      {:ok,
       Map.put(room, :diagnostics, %{
         recent_traces: trace_events(room_id: room.id, limit: 20),
         active_scene: room.active_scene,
         light_count: length(room.lights),
         group_count: length(room.groups)
       })}
    end
  end

  def debug_light(id) do
    with {:ok, light} <- light(id) do
      {:ok,
       Map.put(light, :diagnostics, %{
         physical_state_keys: state_keys(State.get(:light, light.id)),
         desired_state_keys: state_keys(DesiredState.get(:light, light.id)),
         recent_traces: trace_events(entity_kind: :light, entity_id: light.id, limit: 20),
         active_scene: active_scene_for_room(light.room_id)
       })}
    end
  end

  def debug_group(id) do
    with {:ok, group} <- group(id) do
      {:ok,
       Map.put(group, :diagnostics, %{
         physical_state_keys: state_keys(State.get(:group, group.id)),
         desired_state_keys: state_keys(DesiredState.get(:group, group.id)),
         recent_traces: trace_events(entity_kind: :group, entity_id: group.id, limit: 20),
         direct_member_count: length(group.member_light_ids)
       })}
    end
  end

  def traces(filters \\ []) when is_list(filters) do
    TraceBuffer.recent(filters)
    |> Map.update!(:events, fn events -> Enum.map(events, &trace_projection/1) end)
  end

  def control_entity(kind, id, command), do: Control.control_entity(kind, id, command)
  def activate_scene(scene_id), do: Control.activate_scene(scene_id)
  def deactivate_room_scene(room_id), do: Control.deactivate_room_scene(room_id)
  def refresh_physical_state, do: Control.refresh_physical_state()

  defp room_projection(%Room{} = room) do
    active_scene = active_scene_for_room(room.id, room.scenes)

    %{
      id: room.id,
      kind: "room",
      name: room.name,
      display_name: room.display_name || room.name,
      active_scene: active_scene,
      scenes: room.scenes |> Enum.map(&scene_projection/1) |> sort_by_name(),
      presence_inputs:
        room.presence_inputs
        |> Enum.map(&presence_input_projection/1)
        |> sort_by_name(),
      lights: room.lights |> Enum.map(&light_projection/1) |> sort_by_name(),
      groups: room.groups |> Enum.map(&group_projection/1) |> sort_by_name()
    }
  end

  defp room_index_projection(%Room{} = room) do
    %{
      id: room.id,
      kind: "room",
      name: room.name,
      display_name: room.display_name || room.name,
      active_scene: active_scene_for_room(room.id, room.scenes),
      entity_counts: %{
        lights: length(room.lights),
        groups: length(room.groups),
        scenes: length(room.scenes),
        presence_inputs: length(room.presence_inputs)
      }
    }
  end

  defp light_projection(%Light{} = light) do
    physical = State.get(:light, light.id)
    desired = DesiredState.get(:light, light.id)

    %{
      id: light.id,
      kind: "light",
      name: light.name,
      display_name: Util.display_name(light),
      enabled: light.enabled == true,
      source: enum(light.source),
      source_id: light.source_id,
      bridge_id: light.bridge_id,
      room_id: light.room_id,
      canonical_id: light.canonical_light_id,
      capabilities: capabilities(light),
      exports: exports(light),
      physical_state: safe_state(physical),
      physical_observed_at: timestamp(State.observed_at(:light, light.id)),
      desired_state: safe_state(desired),
      desired_revision: DesiredState.revision(:light, light.id),
      desired_updated_at: timestamp(DesiredState.updated_at(:light, light.id)),
      canonical_dependents: canonical_light_dependents(light.id),
      groups: groups_for_light(light.id),
      active_scene: active_scene_for_room(light.room_id)
    }
  end

  defp group_projection(%Group{} = group) do
    member_light_ids = Groups.member_light_ids(group.id) |> Enum.sort()
    member_lights = lights_by_ids(member_light_ids)
    physical = State.get(:group, group.id)
    desired = DesiredState.get(:group, group.id)

    %{
      id: group.id,
      kind: "group",
      name: group.name,
      display_name: Util.display_name(group),
      enabled: group.enabled == true,
      source: enum(group.source),
      source_id: group.source_id,
      bridge_id: group.bridge_id,
      room_id: group.room_id,
      parent_group_id: group.parent_group_id,
      canonical_id: group.canonical_group_id,
      capabilities: capabilities(group),
      exports: exports(group),
      # Group observations are reported by some bridges but are not a substitute
      # for the member-state summary shown alongside them.
      physical_state: safe_state(physical),
      physical_observed_at: timestamp(State.observed_at(:group, group.id)),
      bridge_reported_state: safe_state(physical),
      desired_state: safe_state(desired),
      desired_revision: DesiredState.revision(:group, group.id),
      desired_updated_at: timestamp(DesiredState.updated_at(:group, group.id)),
      member_light_ids: member_light_ids,
      member_lights: member_lights,
      member_power_summary: member_power_summary(member_light_ids)
    }
  end

  defp preload_room(room) do
    Repo.preload(room, [:groups, :lights, :scenes, :presence_inputs])
  end

  defp active_scene_for_room(room_id, scenes \\ [])

  defp active_scene_for_room(nil, _scenes), do: nil

  defp active_scene_for_room(room_id, scenes) do
    case ActiveScenes.get_for_room(room_id) do
      nil ->
        nil

      active_scene ->
        scene =
          Enum.find(scenes, &(&1.id == active_scene.scene_id)) ||
            Repo.get(Scene, active_scene.scene_id)

        %{
          id: active_scene.scene_id,
          kind: "scene",
          name: scene_name(scene),
          room_id: room_id,
          last_applied_at: timestamp(active_scene.last_applied_at),
          power_overrides: power_overrides(active_scene)
        }
    end
  end

  defp scene_projection(%Scene{} = scene) do
    %{
      id: scene.id,
      kind: "scene",
      name: scene_name(scene),
      display_name: scene.display_name || scene.name,
      room_id: scene.room_id
    }
  end

  defp presence_input_projection(input) do
    %{
      id: input.id,
      kind: "presence_input",
      name: input.name,
      occupied: input.occupied == true,
      room_id: input.room_id
    }
  end

  defp entity_search_candidates(kind) when kind in [nil, :light] do
    lights =
      from(light in Light,
        left_join: room in Room,
        on: room.id == light.room_id,
        select: {light, room}
      )
      |> Repo.all()
      |> Enum.map(fn {entity, room} -> %{entity: entity, room: room, kind: "light"} end)

    if kind == :light, do: lights, else: lights ++ entity_search_candidates(:group)
  end

  defp entity_search_candidates(:group) do
    groups_with_members =
      from(membership in GroupLight,
        select: membership.group_id,
        distinct: true
      )
      |> Repo.all()
      |> MapSet.new()

    from(group in Group,
      left_join: room in Room,
      on: room.id == group.room_id,
      select: {group, room}
    )
    |> Repo.all()
    |> Enum.map(fn {entity, room} ->
      %{
        entity: entity,
        room: room,
        kind: "group",
        has_members: MapSet.member?(groups_with_members, entity.id)
      }
    end)
  end

  defp entity_search_candidates(_kind), do: []

  defp entity_search_projection(%{entity: entity, room: room, kind: kind} = candidate, query) do
    display_name = entity.display_name || entity.name
    match = entity_search_match([display_name, entity.name], query)
    canonical_id = canonical_id(entity, kind)

    %{
      id: entity.id,
      kind: kind,
      name: entity.name,
      display_name: display_name,
      room_id: entity.room_id,
      room_name: room && (room.display_name || room.name),
      enabled: entity.enabled == true,
      canonical_id: canonical_id,
      source: enum(entity.source),
      bridge_id: entity.bridge_id,
      match: match && Atom.to_string(match),
      controllable: controllable_search_result?(entity, kind, canonical_id, candidate)
    }
  end

  defp canonical_id(entity, "light"), do: entity.canonical_light_id
  defp canonical_id(entity, "group"), do: entity.canonical_group_id

  defp controllable_search_result?(entity, kind, canonical_id, candidate) do
    entity.enabled == true and is_integer(entity.room_id) and is_nil(canonical_id) and
      (kind == "light" or candidate.has_members == true)
  end

  defp entity_search_match(_names, ""), do: nil

  defp entity_search_match(names, query) do
    normalized_names =
      names
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&normalize_search_value/1)

    cond do
      Enum.any?(normalized_names, &(&1 == query)) -> :exact
      Enum.any?(normalized_names, &String.starts_with?(&1, query)) -> :prefix
      Enum.any?(normalized_names, &String.contains?(&1, query)) -> :partial
      true -> nil
    end
  end

  defp maybe_filter_by_room(results, nil), do: results
  defp maybe_filter_by_room(results, room_id), do: Enum.filter(results, &(&1.room_id == room_id))

  defp entity_search_sort_key(result) do
    {
      search_match_rank(result.match),
      if(result.controllable, do: 0, else: 1),
      normalize_search_value(result.display_name || result.name),
      result.kind,
      result.id
    }
  end

  defp search_match_rank("exact"), do: 0
  defp search_match_rank("prefix"), do: 1
  defp search_match_rank("partial"), do: 2

  defp normalize_search_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_search_value(_value), do: ""

  defp normalize_search_limit(limit) when is_integer(limit) and limit in 1..100, do: limit
  defp normalize_search_limit(_limit), do: 20

  defp canonical_light_dependents(light_id) do
    from(light in Light,
      where: light.canonical_light_id == ^light_id,
      order_by: [asc: light.name]
    )
    |> Repo.all()
    |> Enum.map(&entity_identity(&1, "light"))
  end

  defp groups_for_light(light_id) do
    from(group in Group,
      join: membership in GroupLight,
      on: membership.group_id == group.id,
      where: membership.light_id == ^light_id,
      distinct: true
    )
    |> Repo.all()
    |> Enum.map(&entity_identity(&1, "group"))
    |> sort_by_name()
  end

  defp lights_by_ids([]), do: []

  defp lights_by_ids(light_ids) do
    from(light in Light, where: light.id in ^light_ids)
    |> Repo.all()
    |> Enum.map(&light_projection/1)
    |> sort_by_name()
  end

  defp entity_identity(entity, kind) do
    %{
      id: entity.id,
      kind: kind,
      name: entity.name,
      display_name: Util.display_name(entity),
      enabled: entity.enabled == true
    }
  end

  defp capabilities(entity) do
    kelvin_range =
      if entity.supports_temp == true do
        {min_kelvin, max_kelvin} = Kelvin.derive_range(entity)
        %{"min" => min_kelvin, "max" => max_kelvin}
      else
        nil
      end

    %{
      supports_color: entity.supports_color == true,
      supports_temp: entity.supports_temp == true,
      kelvin_range: kelvin_range
    }
  end

  defp exports(entity) do
    %{
      "home_assistant" => enum(entity.ha_export_mode) || "none",
      "homekit" => enum(entity.homekit_export_mode) || "none"
    }
  end

  defp member_power_summary([]), do: "unknown"

  defp member_power_summary(light_ids) do
    powers =
      Enum.map(light_ids, fn light_id ->
        State.get(:light, light_id)
        |> case do
          %{power: :on} -> :on
          %{power: "on"} -> :on
          %{power: :off} -> :off
          %{power: "off"} -> :off
          _ -> :unknown
        end
      end)

    cond do
      Enum.all?(powers, &(&1 == :on)) -> "on"
      Enum.all?(powers, &(&1 == :off)) -> "off"
      Enum.any?(powers, &(&1 == :unknown)) -> "unknown"
      true -> "mixed"
    end
  end

  defp trace_events(filters) do
    traces(filters).events
  end

  defp trace_projection(event) do
    %{
      sequence: event.sequence,
      recorded_at: timestamp(event.recorded_at),
      trace_id: event.trace_id,
      source: event.source,
      room_id: event.room_id,
      scene_id: event.scene_id,
      stage: enum(event.stage),
      entity_kind: enum(event.entity_kind),
      entity_id: event.entity_id,
      bridge_id: event.bridge_id,
      desired: safe_state(event.desired),
      planner_ms: event.planner_ms,
      action_count: event.action_count,
      queue_delay_ms: event.queue_delay_ms,
      dispatch_ms: event.dispatch_ms,
      total_elapsed_ms: event.total_elapsed_ms,
      result: enum(event.result),
      bridge_count: event.bridge_count,
      recovery_action_count: event.recovery_action_count,
      attempts: event.attempts
    }
  end

  defp safe_state(nil), do: nil

  defp safe_state(state) when is_map(state) do
    state
    |> Map.take(@safe_state_keys)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, Atom.to_string(key), enum(value))
    end)
    |> case do
      empty when map_size(empty) == 0 -> nil
      safe -> safe
    end
  end

  defp safe_state(_state), do: nil

  defp state_keys(nil), do: []

  defp state_keys(state) when is_map(state) do
    state
    |> Map.keys()
    |> Enum.filter(&(&1 in @safe_state_keys))
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
  end

  defp state_keys(_state), do: []

  defp power_overrides(active_scene) do
    active_scene
    |> ActiveScenes.power_overrides()
    |> Map.new(fn {light_id, power} -> {Integer.to_string(light_id), enum(power)} end)
  end

  defp sort_by_name(entities) do
    Enum.sort_by(entities, fn entity ->
      Map.get(entity, :display_name) || Map.get(entity, :name) || ""
    end)
  end

  defp scene_name(nil), do: nil
  defp scene_name(scene), do: scene.display_name || scene.name

  defp process_running?(module), do: is_pid(Process.whereis(module))

  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(_value), do: nil

  defp enum(nil), do: nil
  defp enum(value) when is_atom(value), do: Atom.to_string(value)
  defp enum(value), do: value
end
