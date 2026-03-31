defmodule HueworksWeb.LightsLive do
  use Phoenix.LiveView
  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.Scenes
  alias Hueworks.Control.{DesiredState, Executor, Planner, State}
  alias Hueworks.Repo
  alias Hueworks.Groups
  alias Hueworks.Lights
  alias Hueworks.Rooms
  alias Hueworks.Schemas.GroupLight
  alias HueworksWeb.FilterPrefs
  alias Hueworks.Util

  @impl true
  def mount(params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
    end

    filter_session_id = session["filter_session_id"]
    prefs = FilterPrefs.get(filter_session_id)

    rooms = Rooms.list_rooms()
    groups = Groups.list_controllable_groups(true)
    lights = Lights.list_controllable_lights(true, true)
    group_state = build_group_state(groups)
    light_state = build_light_state(lights)
    group_filter = Util.parse_filter(prefs[:group_filter] || params["group_filter"])
    light_filter = Util.parse_filter(prefs[:light_filter] || params["light_filter"])

    group_room_filter =
      Util.parse_room_filter(prefs[:group_room_filter] || params["group_room_filter"])

    light_room_filter =
      Util.parse_room_filter(prefs[:light_room_filter] || params["light_room_filter"])

    group_room_filter = Util.normalize_room_filter(group_room_filter, rooms)
    light_room_filter = Util.normalize_room_filter(light_room_filter, rooms)

    if is_binary(filter_session_id) do
      FilterPrefs.update(filter_session_id, %{
        group_room_filter: group_room_filter,
        light_room_filter: light_room_filter
      })
    end

    show_disabled_groups = prefs[:show_disabled_groups] || false
    show_disabled_lights = prefs[:show_disabled_lights] || false
    show_linked_lights = prefs[:show_linked_lights] || false

    {:ok,
     assign(socket,
       filter_session_id: filter_session_id,
       rooms: rooms,
       groups: groups,
       lights: lights,
       group_filter: group_filter,
       light_filter: light_filter,
       group_room_filter: group_room_filter,
       light_room_filter: light_room_filter,
       group_state: group_state,
       light_state: light_state,
       status: nil,
       edit_modal_open: false,
       edit_target_type: nil,
       edit_target_id: nil,
       edit_name: nil,
       edit_display_name: "",
       edit_show_link_selector: false,
       edit_canonical_light_id: nil,
       edit_link_targets: [],
       edit_room_id: nil,
       edit_actual_min_kelvin: "",
       edit_actual_max_kelvin: "",
       edit_reported_min_kelvin: "",
       edit_reported_max_kelvin: "",
       edit_enabled: true,
       edit_mapping_supported: false,
       edit_extended_kelvin_range: false,
       show_disabled_groups: show_disabled_groups,
       show_disabled_lights: show_disabled_lights,
       show_linked_lights: show_linked_lights
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    updates =
      %{}
      |> maybe_put_param(:group_filter, params["group_filter"])
      |> maybe_put_param(:light_filter, params["light_filter"])
      |> maybe_put_param(:group_room_filter, params["group_room_filter"])
      |> maybe_put_param(:light_room_filter, params["light_room_filter"])

    if map_size(updates) > 0 do
      {:noreply, store_filter_prefs(socket, updates)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    :ok = State.suppress_scene_clear_for_refresh()
    State.bootstrap()

    socket =
      socket
      |> reload_entities()
      |> assign(status: "Reloaded database snapshot")

    {:noreply, socket}
  end

  def handle_event("set_group_filter", %{"group_filter" => filter}, socket) do
    {:noreply, store_filter_prefs(socket, group_filter: Util.parse_filter(filter))}
  end

  def handle_event("set_group_room_filter", %{"group_room_filter" => filter}, socket) do
    filter = Util.parse_room_filter(filter)

    {:noreply,
     store_filter_prefs(socket,
       group_room_filter: Util.normalize_room_filter(filter, socket.assigns.rooms)
     )}
  end

  def handle_event("set_light_filter", %{"light_filter" => filter}, socket) do
    {:noreply, store_filter_prefs(socket, light_filter: Util.parse_filter(filter))}
  end

  def handle_event("set_light_room_filter", %{"light_room_filter" => filter}, socket) do
    filter = Util.parse_room_filter(filter)

    {:noreply,
     store_filter_prefs(socket,
       light_room_filter: Util.normalize_room_filter(filter, socket.assigns.rooms)
     )}
  end

  def handle_event("toggle_group_disabled", %{"show_disabled_groups" => value}, socket) do
    {:noreply, store_filter_prefs(socket, show_disabled_groups: value == "true")}
  end

  def handle_event("toggle_group_disabled", _params, socket) do
    {:noreply, store_filter_prefs(socket, show_disabled_groups: false)}
  end

  def handle_event("toggle_light_disabled", %{"show_disabled_lights" => value}, socket) do
    {:noreply, store_filter_prefs(socket, show_disabled_lights: value == "true")}
  end

  def handle_event("toggle_light_disabled", _params, socket) do
    {:noreply, store_filter_prefs(socket, show_disabled_lights: false)}
  end

  def handle_event("toggle_light_linked", %{"show_linked_lights" => value}, socket) do
    {:noreply, store_filter_prefs(socket, show_linked_lights: value == "true")}
  end

  def handle_event("toggle_light_linked", _params, socket) do
    {:noreply, store_filter_prefs(socket, show_linked_lights: false)}
  end

  def handle_event("open_edit", %{"type" => type, "id" => id}, socket) do
    case fetch_edit_target(type, id) do
      {:ok, target} ->
        link_targets = edit_link_targets(type, target)
        canonical_light_id = canonical_light_id_for(type, target)

        {:noreply,
         assign(socket,
           edit_modal_open: true,
           edit_target_type: type,
           edit_target_id: target.id,
           edit_name: Util.display_name(target),
           edit_display_name: target.display_name || "",
           edit_show_link_selector: type == "light" and not is_nil(canonical_light_id),
           edit_canonical_light_id: canonical_light_id,
           edit_link_targets: link_targets,
           edit_room_id: target.room_id,
           edit_actual_min_kelvin: Util.format_integer(target.actual_min_kelvin),
           edit_actual_max_kelvin: Util.format_integer(target.actual_max_kelvin),
           edit_reported_min_kelvin: Util.format_integer(target.reported_min_kelvin),
           edit_reported_max_kelvin: Util.format_integer(target.reported_max_kelvin),
           edit_enabled: target.enabled,
           edit_mapping_supported: Hueworks.Kelvin.mapping_supported?(target),
           edit_extended_kelvin_range: target.extended_kelvin_range
         )}

      {:error, reason} ->
        {:noreply, assign(socket, status: "ERROR #{type} #{id}: #{Util.format_reason(reason)}")}
    end
  end

  def handle_event("close_edit", _params, socket) do
    {:noreply, close_edit_modal(socket)}
  end

  def handle_event("show_link_selector", _params, socket) do
    {:noreply, assign(socket, edit_show_link_selector: true)}
  end

  def handle_event("update_display_name", %{"display_name" => display_name}, socket) do
    {:noreply, assign_edit_fields(socket, %{"display_name" => display_name})}
  end

  def handle_event("save_display_name", %{"display_name" => display_name}, socket) do
    case save_display_name(socket, %{"display_name" => display_name}) do
      {:ok, socket} -> {:noreply, socket}
      {:error, reason, socket} -> {:noreply, assign(socket, status: reason)}
    end
  end

  def handle_event("update_edit_fields", params, socket) do
    {:noreply, assign_edit_fields(socket, params)}
  end

  def handle_event("save_edit_fields", params, socket) do
    case save_display_name(socket, params) do
      {:ok, socket} -> {:noreply, socket}
      {:error, reason, socket} -> {:noreply, assign(socket, status: reason)}
    end
  end

  def handle_event("toggle_on", %{"type" => type, "id" => id}, socket) do
    {:noreply, dispatch_action(socket, type, id, :on)}
  end

  def handle_event("toggle_off", %{"type" => type, "id" => id}, socket) do
    {:noreply, dispatch_action(socket, type, id, :off)}
  end

  def handle_event("toggle", %{"type" => type, "id" => id}, socket) do
    {:noreply, dispatch_toggle(socket, type, id)}
  end

  def handle_event("set_brightness", %{"type" => type, "id" => id, "level" => level}, socket) do
    {:noreply, dispatch_action(socket, type, id, {:brightness, level})}
  end

  def handle_event("set_color_temp", %{"type" => type, "id" => id, "kelvin" => kelvin}, socket) do
    {:noreply, dispatch_action(socket, type, id, {:color_temp, kelvin})}
  end

  @impl true
  def handle_info({:control_state, :light, id, state}, socket) do
    merged_state =
      socket.assigns.light_state
      |> Map.get(id, %{})
      |> merge_light_state_for_display(light_for_id(socket.assigns.lights, id), state)

    {:noreply,
     socket
     |> assign(:light_state, Map.put(socket.assigns.light_state, id, merged_state))}
  end

  @impl true
  def handle_info({:control_state, :group, id, state}, socket) do
    {:noreply,
     socket
     |> assign(
       :group_state,
       Map.update(socket.assigns.group_state, id, state, &merge_state(&1, state))
     )}
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  defp dispatch_action(socket, "light", id, {:brightness, level}) do
    with {:ok, light} <- fetch_light(id),
         {:ok, parsed} <- Util.parse_level(level),
         {:ok, _diff} <- apply_manual_updates(light.room_id, [light.id], %{brightness: parsed}) do
      _ = ActiveScenes.handle_manual_change(light.room_id, %{brightness: parsed})

      socket
      |> update_light_state_assign(light.id, %{brightness: parsed})
      |> assign(status: "BRIGHTNESS light #{Util.display_name(light)} -> #{parsed}%")
    else
      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, {:color_temp, kelvin}) do
    with {:ok, light} <- fetch_light(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         {:ok, _diff} <- apply_manual_updates(light.room_id, [light.id], %{kelvin: parsed}) do
      _ = ActiveScenes.handle_manual_change(light.room_id, %{kelvin: parsed})

      socket
      |> update_light_state_assign(light.id, %{kelvin: parsed})
      |> assign(status: "TEMP light #{Util.display_name(light)} -> #{parsed}K")
    else
      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:brightness, level}) do
    with {:ok, group} <- fetch_group(id),
         {:ok, parsed} <- Util.parse_level(level),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <- apply_manual_updates(group.room_id, light_ids, %{brightness: parsed}) do
      _ = ActiveScenes.handle_manual_change(group.room_id, %{brightness: parsed})

      socket
      |> update_group_state_assign(group.id, %{brightness: parsed})
      |> assign(status: "BRIGHTNESS group #{Util.display_name(group)} -> #{parsed}%")
    else
      [] ->
        assign(socket, status: "ERROR group #{id}: no_members")

      {:error, reason} ->
        assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:color_temp, kelvin}) do
    with {:ok, group} <- fetch_group(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <- apply_manual_updates(group.room_id, light_ids, %{kelvin: parsed}) do
      _ = ActiveScenes.handle_manual_change(group.room_id, %{kelvin: parsed})

      socket
      |> update_group_state_assign(group.id, %{kelvin: parsed})
      |> assign(status: "TEMP group #{Util.display_name(group)} -> #{parsed}K")
    else
      [] ->
        assign(socket, status: "ERROR group #{id}: no_members")

      {:error, reason} ->
        assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, action) do
    with {:ok, light} <- fetch_light(id),
         {:ok, updated_attrs} <- apply_manual_power_action(light.room_id, [light.id], action) do
      _ = ActiveScenes.handle_manual_change(light.room_id, %{power: action})

      socket
      |> update_light_state_assign(light.id, updated_attrs)
      |> assign(status: "#{action_label(action)} light #{Util.display_name(light)}")
    else
      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, action) do
    with {:ok, group} <- fetch_group(id),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, updated_attrs} <- apply_manual_power_action(group.room_id, light_ids, action) do
      _ = ActiveScenes.handle_manual_change(group.room_id, %{power: action})

      socket
      |> update_group_state_assign(group.id, updated_attrs)
      |> assign(status: "#{action_label(action)} group #{Util.display_name(group)}")
    else
      [] ->
        assign(socket, status: "ERROR group #{id}: no_members")

      {:error, reason} ->
        assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, type, id, _action) do
    assign(socket, status: "ERROR #{type} #{id}: unsupported")
  end

  defp dispatch_toggle(socket, "light", id) do
    with {:ok, light} <- fetch_light(id) do
      action = toggle_action(socket.assigns.light_state, light.id)
      dispatch_action(socket, "light", id, action)
    else
      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_toggle(socket, "group", id) do
    with {:ok, group} <- fetch_group(id) do
      action = toggle_action(socket.assigns.group_state, group.id)
      dispatch_action(socket, "group", id, action)
    else
      {:error, reason} ->
        assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_toggle(socket, type, id) do
    assign(socket, status: "ERROR #{type} #{id}: unsupported")
  end

  defp toggle_action(state_map, id) do
    case Map.get(state_map, id, %{}) do
      %{power: power} when power in [:on, "on", true] -> :off
      _ -> :on
    end
  end

  defp fetch_edit_target("light", id), do: fetch_light(id)
  defp fetch_edit_target("group", id), do: fetch_group(id)
  defp fetch_edit_target(_type, _id), do: {:error, :invalid_type}

  defp save_display_name(socket, params) do
    type = socket.assigns.edit_target_type
    id = socket.assigns.edit_target_id
    attrs = normalize_edit_attrs(params)

    with {:ok, target} <- fetch_edit_target(type, to_string(id)),
         {:ok, updated} <- apply_display_name(type, target, attrs) do
      socket =
        socket
        |> reload_entities()
        |> close_edit_modal()
        |> assign(status: "Saved #{type} #{Util.display_name(updated)}")

      {:ok, socket}
    else
      {:error, reason} ->
        {:error, "ERROR #{type} #{id}: #{Util.format_reason(reason)}", socket}
    end
  end

  defp apply_display_name("light", light, attrs), do: Lights.update_display_name(light, attrs)
  defp apply_display_name("group", group, attrs), do: Groups.update_display_name(group, attrs)
  defp apply_display_name(_type, _target, _attrs), do: {:error, :invalid_type}

  defp edit_link_targets("light", light), do: Lights.list_link_targets(light)
  defp edit_link_targets(_type, _target), do: []

  defp canonical_light_id_for("light", light), do: light.canonical_light_id
  defp canonical_light_id_for(_type, _target), do: nil

  defp reload_entities(socket) do
    rooms = Rooms.list_rooms()
    groups = Groups.list_controllable_groups(true)
    lights = Lights.list_controllable_lights(true, true)
    group_room_filter = Util.normalize_room_filter(socket.assigns.group_room_filter, rooms)
    light_room_filter = Util.normalize_room_filter(socket.assigns.light_room_filter, rooms)
    group_state = build_group_state(groups)
    light_state = build_light_state(lights)

    assign(socket,
      rooms: rooms,
      groups: groups,
      lights: lights,
      group_room_filter: group_room_filter,
      light_room_filter: light_room_filter,
      group_state: group_state,
      light_state: light_state
    )
  end

  defp close_edit_modal(socket) do
    assign(socket,
      edit_modal_open: false,
      edit_target_type: nil,
      edit_target_id: nil,
      edit_name: nil,
      edit_display_name: "",
      edit_show_link_selector: false,
      edit_canonical_light_id: nil,
      edit_link_targets: [],
      edit_room_id: nil,
      edit_actual_min_kelvin: "",
      edit_actual_max_kelvin: "",
      edit_reported_min_kelvin: "",
      edit_reported_max_kelvin: "",
      edit_enabled: true,
      edit_mapping_supported: false,
      edit_extended_kelvin_range: false
    )
  end

  defp assign_edit_fields(socket, params) do
    assign(socket,
      edit_display_name: Map.get(params, "display_name", socket.assigns.edit_display_name),
      edit_canonical_light_id:
        Util.parse_optional_integer(
          Map.get(params, "canonical_light_id", socket.assigns.edit_canonical_light_id)
        ),
      edit_actual_min_kelvin:
        Map.get(params, "actual_min_kelvin", socket.assigns.edit_actual_min_kelvin),
      edit_actual_max_kelvin:
        Map.get(params, "actual_max_kelvin", socket.assigns.edit_actual_max_kelvin),
      edit_room_id:
        Util.parse_optional_integer(Map.get(params, "room_id", socket.assigns.edit_room_id)),
      edit_enabled:
        Util.parse_optional_bool(Map.get(params, "enabled", socket.assigns.edit_enabled)),
      edit_extended_kelvin_range:
        Util.parse_optional_bool(
          Map.get(params, "extended_kelvin_range", socket.assigns.edit_extended_kelvin_range)
        )
    )
  end

  defp normalize_edit_attrs(params) do
    room_id =
      if Map.has_key?(params, "room_id") do
        Util.parse_optional_integer(Map.get(params, "room_id"))
      else
        :skip
      end

    [
      display_name: Map.get(params, "display_name"),
      canonical_light_id:
        if Map.has_key?(params, "canonical_light_id") do
          Util.parse_optional_integer(Map.get(params, "canonical_light_id"))
        else
          :skip
        end,
      room_id: room_id,
      actual_min_kelvin: Util.parse_optional_integer(Map.get(params, "actual_min_kelvin")),
      actual_max_kelvin: Util.parse_optional_integer(Map.get(params, "actual_max_kelvin")),
      extended_kelvin_range: Util.parse_optional_bool(Map.get(params, "extended_kelvin_range")),
      enabled: Util.parse_optional_bool(Map.get(params, "enabled"))
    ]
    |> Enum.reject(fn
      {_key, :skip} -> true
      {:room_id, _} -> false
      {:canonical_light_id, _} -> false
      {_key, value} -> is_nil(value)
    end)
    |> Map.new()
  end

  defp apply_manual_updates(room_id, light_ids, desired_update)
       when is_list(light_ids) and is_map(desired_update) do
    txn = DesiredState.begin(:manual_ui)

    txn =
      Enum.reduce(light_ids, txn, fn light_id, acc ->
        DesiredState.apply(acc, :light, light_id, desired_update)
      end)

    case DesiredState.commit(txn) do
      {:ok, %{intent_diff: intent_diff}} ->
        _ = enqueue_diff(room_id, intent_diff)
        {:ok, intent_diff}

      other ->
        other
    end
  end

  defp apply_manual_power_action(room_id, light_ids, :on)
       when is_integer(room_id) and is_list(light_ids) do
    trace = %{
      trace_id: "manual-on-#{room_id}-#{System.unique_integer([:positive])}",
      source: "lights_live.manual_power_on",
      started_at_ms: System.monotonic_time(:millisecond)
    }

    case Scenes.reapply_active_scene_lights(room_id, light_ids,
           power_override: :on,
           trace: trace
         ) do
      {:ok, _diff, updated} when map_size(updated) > 0 ->
        {:ok, merged_updated_light_attrs(updated, light_ids)}

      {:ok, _diff, _updated} ->
        with {:ok, _diff} <- apply_manual_updates(room_id, light_ids, %{power: :on}) do
          {:ok, %{power: :on}}
        end

      other ->
        other
    end
  end

  defp apply_manual_power_action(room_id, light_ids, action)
       when is_integer(room_id) and is_list(light_ids) and action in [:off, "off"] do
    with {:ok, _diff} <- apply_manual_updates(room_id, light_ids, %{power: :off}) do
      {:ok, %{power: :off}}
    end
  end

  defp enqueue_diff(_room_id, diff) when map_size(diff) == 0, do: :ok

  defp enqueue_diff(room_id, diff) when is_integer(room_id) and is_map(diff) do
    plan = Planner.plan_room(room_id, diff)
    _ = Executor.enqueue(plan)
    :ok
  end

  defp enqueue_diff(_room_id, diff) when is_map(diff) do
    light_ids =
      diff
      |> Map.keys()
      |> Enum.flat_map(fn
        {:light, id} when is_integer(id) -> [id]
        {"light", id} when is_integer(id) -> [id]
        _ -> []
      end)
      |> Enum.uniq()

    bridge_by_light_id =
      Repo.all(
        from(l in Hueworks.Schemas.Light,
          where: l.id in ^light_ids,
          select: {l.id, l.bridge_id}
        )
      )
      |> Map.new()

    plan =
      diff
      |> Enum.flat_map(fn
        {{:light, id}, desired} when is_integer(id) and is_map(desired) ->
          case Map.get(bridge_by_light_id, id) do
            nil -> []
            bridge_id -> [%{type: :light, id: id, bridge_id: bridge_id, desired: desired}]
          end

        {{"light", id}, desired} when is_integer(id) and is_map(desired) ->
          case Map.get(bridge_by_light_id, id) do
            nil -> []
            bridge_id -> [%{type: :light, id: id, bridge_id: bridge_id, desired: desired}]
          end

        _ ->
          []
      end)

    _ = Executor.enqueue(plan)
    :ok
  end

  defp group_light_ids(group_id) when is_integer(group_id) do
    Repo.all(
      from(gl in GroupLight,
        where: gl.group_id == ^group_id,
        select: gl.light_id
      )
    )
  end

  defp merged_updated_light_attrs(updated, light_ids) do
    light_ids
    |> Enum.reduce(%{}, fn light_id, acc ->
      Map.merge(acc, Map.get(updated, {:light, light_id}, %{}))
    end)
  end

  defp fetch_light(id) do
    case Integer.parse(id) do
      {light_id, ""} ->
        case Lights.get_light(light_id) do
          nil -> {:error, :not_found}
          light -> {:ok, light}
        end

      _ ->
        {:error, :invalid_id}
    end
  end

  defp fetch_group(id) do
    case Integer.parse(id) do
      {group_id, ""} ->
        case Groups.get_group(group_id) do
          nil -> {:error, :not_found}
          group -> {:ok, group}
        end

      _ ->
        {:error, :invalid_id}
    end
  end

  defp action_label(:on), do: "ON"
  defp action_label(:off), do: "OFF"
  defp action_label(_action), do: "ACTION"

  defp build_group_state(groups) do
    Enum.reduce(groups, %{}, fn group, acc ->
      {min_k, max_k} = Hueworks.Kelvin.derive_range(group)
      kelvin = round((min_k + max_k) / 2)

      state =
        State.ensure(:group, group.id, %{
          brightness: 75,
          kelvin: kelvin,
          power: :off
        })

      Map.put(acc, group.id, state)
    end)
  end

  defp build_light_state(lights) do
    Enum.reduce(lights, %{}, fn light, acc ->
      {min_k, max_k} = Hueworks.Kelvin.derive_range(light)
      kelvin = round((min_k + max_k) / 2)

      state =
        State.ensure(:light, light.id, %{
          brightness: 75,
          kelvin: kelvin,
          power: :off
        })

      Map.put(acc, light.id, state)
    end)
  end

  defp merge_state(existing, updates) do
    Map.merge(existing, updates)
  end

  defp merge_light_state_for_display(existing, nil, updates), do: merge_state(existing, updates)

  defp merge_light_state_for_display(existing, light, updates) do
    merged = merge_state(existing, updates)

    if preserve_extended_display_kelvin?(light, existing, updates) do
      Map.put(merged, :kelvin, existing[:kelvin])
    else
      merged
    end
  end

  defp preserve_extended_display_kelvin?(%{extended_kelvin_range: true}, existing, updates) do
    current_kelvin = existing[:kelvin]
    incoming_kelvin = updates[:kelvin]

    is_number(current_kelvin) and current_kelvin < 2700 and is_number(incoming_kelvin) and
      incoming_kelvin >= 2700
  end

  defp preserve_extended_display_kelvin?(_light, _existing, _updates), do: false

  defp light_for_id(lights, id) do
    Enum.find(lights, &(&1.id == id))
  end

  defp update_light_state_assign(socket, light_id, attrs)
       when is_integer(light_id) and is_map(attrs) do
    assign(
      socket,
      :light_state,
      Map.update(socket.assigns.light_state, light_id, attrs, &merge_state(&1, attrs))
    )
  end

  defp update_group_state_assign(socket, group_id, attrs)
       when is_integer(group_id) and is_map(attrs) do
    assign(
      socket,
      :group_state,
      Map.update(socket.assigns.group_state, group_id, attrs, &merge_state(&1, attrs))
    )
  end

  defp get_state_value(state_map, id, key, fallback) do
    state_map
    |> Map.get(id, %{})
    |> Map.get(key, fallback)
  end

  defp filter_entities(entities, filter, room_filter, show_disabled) do
    entities
    |> filter_by_source(filter)
    |> filter_by_room(room_filter)
    |> filter_by_enabled(show_disabled)
  end

  defp filter_lights(entities, filter, room_filter, show_disabled, show_linked) do
    entities
    |> filter_entities(filter, room_filter, show_disabled)
    |> filter_by_linked(show_linked)
  end

  defp filter_by_source(entities, "all"), do: entities

  defp filter_by_source(entities, filter) when is_binary(filter) do
    case Util.parse_source_filter(filter) do
      {:ok, source} -> Enum.filter(entities, &(&1.source == source))
      :error -> entities
    end
  end

  defp filter_by_source(entities, _filter), do: entities

  defp filter_by_enabled(entities, true), do: entities

  defp filter_by_enabled(entities, _show_disabled) do
    Enum.filter(entities, &(&1.enabled != false))
  end

  defp filter_by_linked(entities, true), do: entities

  defp filter_by_linked(entities, _show_linked) do
    Enum.filter(entities, &is_nil(&1.canonical_light_id))
  end

  defp filter_by_room(entities, "all"), do: entities

  defp filter_by_room(entities, "unassigned") do
    Enum.filter(entities, &is_nil(&1.room_id))
  end

  defp filter_by_room(entities, nil), do: entities

  defp filter_by_room(entities, room_id) when is_integer(room_id) do
    Enum.filter(entities, &(&1.room_id == room_id))
  end

  defp filter_by_room(entities, _room_id), do: entities

  defp store_filter_prefs(socket, updates) do
    updates = Map.new(updates)
    session_id = socket.assigns.filter_session_id

    if is_binary(session_id) do
      FilterPrefs.update(session_id, updates)
    end

    assign(socket, updates)
  end

  defp maybe_put_param(acc, _key, nil), do: acc
  defp maybe_put_param(acc, _key, ""), do: acc
  defp maybe_put_param(acc, key, value), do: Map.put(acc, key, value)
end
