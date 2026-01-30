defmodule HueworksWeb.LightsLive do
  use Phoenix.LiveView

  alias Hueworks.Control
  alias Hueworks.Control.State
  alias Hueworks.Groups
  alias Hueworks.Lights
  alias Hueworks.Rooms
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
    lights = Lights.list_controllable_lights(true)
    group_state = build_group_state(groups)
    light_state = build_light_state(lights)
    group_filter = Util.parse_filter(prefs[:group_filter] || params["group_filter"])
    light_filter = Util.parse_filter(prefs[:light_filter] || params["light_filter"])
    group_room_filter = Util.parse_room_filter(prefs[:group_room_filter] || params["group_room_filter"])
    light_room_filter = Util.parse_room_filter(prefs[:light_room_filter] || params["light_room_filter"])
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
       edit_room_id: nil,
       edit_actual_min_kelvin: "",
       edit_actual_max_kelvin: "",
       edit_reported_min_kelvin: "",
       edit_reported_max_kelvin: "",
       edit_enabled: true,
       edit_mapping_supported: false,
       edit_extended_kelvin_range: false,
       show_disabled_groups: show_disabled_groups,
       show_disabled_lights: show_disabled_lights
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
    {:noreply, store_filter_prefs(socket, group_room_filter: Util.normalize_room_filter(filter, socket.assigns.rooms))}
  end

  def handle_event("set_light_filter", %{"light_filter" => filter}, socket) do
    {:noreply, store_filter_prefs(socket, light_filter: Util.parse_filter(filter))}
  end

  def handle_event("set_light_room_filter", %{"light_room_filter" => filter}, socket) do
    filter = Util.parse_room_filter(filter)
    {:noreply, store_filter_prefs(socket, light_room_filter: Util.normalize_room_filter(filter, socket.assigns.rooms))}
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

  def handle_event("open_edit", %{"type" => type, "id" => id}, socket) do
    case fetch_edit_target(type, id) do
      {:ok, target} ->
        {:noreply,
         assign(socket,
          edit_modal_open: true,
          edit_target_type: type,
          edit_target_id: target.id,
          edit_name: target.name,
          edit_display_name: target.display_name || "",
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
    {:noreply,
     socket
     |> assign(:light_state, Map.update(socket.assigns.light_state, id, state, &merge_state(&1, state)))}
  end

  @impl true
  def handle_info({:control_state, :group, id, state}, socket) do
    {:noreply,
     socket
     |> assign(:group_state, Map.update(socket.assigns.group_state, id, state, &merge_state(&1, state)))}
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  defp dispatch_action(socket, "light", id, {:brightness, level}) do
    with {:ok, light} <- fetch_light(id),
         {:ok, parsed} <- Util.parse_level(level),
         :ok <- Control.Light.set_brightness(light, parsed) do
      State.put(:light, light.id, %{brightness: parsed})

      socket
      |> assign(:light_state, Map.update(socket.assigns.light_state, light.id, %{brightness: parsed}, &merge_state(&1, %{brightness: parsed})))
      |> assign(status: "BRIGHTNESS light #{light.name} -> #{parsed}%")
    else
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, {:color_temp, kelvin}) do
    with {:ok, light} <- fetch_light(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         :ok <- Control.Light.set_color_temp(light, parsed) do
      State.put(:light, light.id, %{kelvin: parsed})

      socket
      |> assign(:light_state, Map.update(socket.assigns.light_state, light.id, %{kelvin: parsed}, &merge_state(&1, %{kelvin: parsed})))
      |> assign(status: "TEMP light #{light.name} -> #{parsed}K")
    else
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:brightness, level}) do
    with {:ok, group} <- fetch_group(id),
         {:ok, parsed} <- Util.parse_level(level),
         :ok <- Control.Group.set_brightness(group, parsed) do
      State.put(:group, group.id, %{brightness: parsed})

      socket
      |> assign(:group_state, Map.update(socket.assigns.group_state, group.id, %{brightness: parsed}, &merge_state(&1, %{brightness: parsed})))
      |> assign(status: "BRIGHTNESS group #{group.name} -> #{parsed}%")
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:color_temp, kelvin}) do
    with {:ok, group} <- fetch_group(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         :ok <- Control.Group.set_color_temp(group, parsed) do
      State.put(:group, group.id, %{kelvin: parsed})

      socket
      |> assign(:group_state, Map.update(socket.assigns.group_state, group.id, %{kelvin: parsed}, &merge_state(&1, %{kelvin: parsed})))
      |> assign(status: "TEMP group #{group.name} -> #{parsed}K")
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, action) do
    with {:ok, light} <- fetch_light(id),
         :ok <- apply_light_action(light, action) do
      State.put(:light, light.id, %{power: action})

      socket
      |> assign(:light_state, Map.update(socket.assigns.light_state, light.id, %{power: action}, &merge_state(&1, %{power: action})))
      |> assign(status: "#{action_label(action)} light #{light.name}")
    else
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, action) do
    with {:ok, group} <- fetch_group(id),
         :ok <- apply_group_action(group, action) do
      State.put(:group, group.id, %{power: action})

      socket
      |> assign(:group_state, Map.update(socket.assigns.group_state, group.id, %{power: action}, &merge_state(&1, %{power: action})))
      |> assign(status: "#{action_label(action)} group #{group.name}")
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
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
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_toggle(socket, "group", id) do
    with {:ok, group} <- fetch_group(id) do
      action = toggle_action(socket.assigns.group_state, group.id)
      dispatch_action(socket, "group", id, action)
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
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
        |> assign(status: "Saved #{type} #{updated.name}")

      {:ok, socket}
    else
      {:error, reason} ->
        {:error, "ERROR #{type} #{id}: #{Util.format_reason(reason)}", socket}
    end
  end

  defp apply_display_name("light", light, attrs), do: Lights.update_display_name(light, attrs)
  defp apply_display_name("group", group, attrs), do: Groups.update_display_name(group, attrs)
  defp apply_display_name(_type, _target, _attrs), do: {:error, :invalid_type}

  defp reload_entities(socket) do
    rooms = Rooms.list_rooms()
    groups = Groups.list_controllable_groups(true)
    lights = Lights.list_controllable_lights(true)
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
      edit_actual_min_kelvin:
        Map.get(params, "actual_min_kelvin", socket.assigns.edit_actual_min_kelvin),
      edit_actual_max_kelvin:
        Map.get(params, "actual_max_kelvin", socket.assigns.edit_actual_max_kelvin),
      edit_room_id:
        Util.parse_optional_integer(Map.get(params, "room_id", socket.assigns.edit_room_id)),
      edit_enabled: Util.parse_optional_bool(Map.get(params, "enabled", socket.assigns.edit_enabled)),
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
      room_id: room_id,
      actual_min_kelvin: Util.parse_optional_integer(Map.get(params, "actual_min_kelvin")),
      actual_max_kelvin: Util.parse_optional_integer(Map.get(params, "actual_max_kelvin")),
      extended_kelvin_range: Util.parse_optional_bool(Map.get(params, "extended_kelvin_range")),
      enabled: Util.parse_optional_bool(Map.get(params, "enabled"))
    ]
    |> Enum.reject(fn
      {_key, :skip} -> true
      {:room_id, _} -> false
      {_key, value} -> is_nil(value)
    end)
    |> Map.new()
  end

  defp apply_light_action(light, :on), do: Control.Light.on(light)
  defp apply_light_action(light, :off), do: Control.Light.off(light)

  defp apply_group_action(group, :on), do: Control.Group.on(group)
  defp apply_group_action(group, :off), do: Control.Group.off(group)

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
