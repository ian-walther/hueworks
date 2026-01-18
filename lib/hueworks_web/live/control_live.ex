defmodule HueworksWeb.ControlLive do
  use Phoenix.LiveView

  import Phoenix.Component

  embed_templates "control_live/*"

  alias Hueworks.Control
  alias Hueworks.Control.State
  alias Hueworks.Groups
  alias Hueworks.Lights

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
    end

    groups = Groups.list_controllable_groups(true)
    lights = Lights.list_controllable_lights(true)
    group_state = build_group_state(groups)
    light_state = build_light_state(lights)
    group_filter = parse_filter(params["group_filter"])
    light_filter = parse_filter(params["light_filter"])

    {:ok,
     assign(socket,
       groups: groups,
       lights: lights,
       group_filter: group_filter,
       light_filter: light_filter,
       group_state: group_state,
       light_state: light_state,
       status: nil,
       edit_modal_open: false,
       edit_target_type: nil,
       edit_target_id: nil,
       edit_name: nil,
       edit_display_name: "",
       edit_actual_min_kelvin: "",
       edit_actual_max_kelvin: "",
       edit_reported_min_kelvin: "",
       edit_reported_max_kelvin: "",
       edit_enabled: true,
       edit_mapping_supported: false,
       edit_extended_kelvin_range: false,
       show_disabled_groups: false,
       show_disabled_lights: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket,
       group_filter: parse_filter(params["group_filter"]),
       light_filter: parse_filter(params["light_filter"])
     )}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    State.bootstrap()
    groups = Groups.list_controllable_groups(true)
    lights = Lights.list_controllable_lights(true)
    group_state = build_group_state(groups)
    light_state = build_light_state(lights)

    {:noreply,
     assign(socket,
       groups: groups,
       lights: lights,
       group_state: group_state,
       light_state: light_state,
        status: "Reloaded database snapshot"
     )}
  end

  def handle_event("set_group_filter", %{"group_filter" => filter}, socket) do
    {:noreply, push_filter_patch(socket, group_filter: filter)}
  end

  def handle_event("set_light_filter", %{"light_filter" => filter}, socket) do
    {:noreply, push_filter_patch(socket, light_filter: filter)}
  end

  def handle_event("toggle_group_disabled", %{"show_disabled_groups" => value}, socket) do
    {:noreply, assign(socket, show_disabled_groups: value == "true")}
  end

  def handle_event("toggle_group_disabled", _params, socket) do
    {:noreply, assign(socket, show_disabled_groups: false)}
  end

  def handle_event("toggle_light_disabled", %{"show_disabled_lights" => value}, socket) do
    {:noreply, assign(socket, show_disabled_lights: value == "true")}
  end

  def handle_event("toggle_light_disabled", _params, socket) do
    {:noreply, assign(socket, show_disabled_lights: false)}
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
          edit_actual_min_kelvin: format_kelvin(target.actual_min_kelvin),
          edit_actual_max_kelvin: format_kelvin(target.actual_max_kelvin),
          edit_reported_min_kelvin: format_kelvin(target.reported_min_kelvin),
          edit_reported_max_kelvin: format_kelvin(target.reported_max_kelvin),
          edit_enabled: target.enabled,
          edit_mapping_supported: Hueworks.Kelvin.mapping_supported?(target),
          edit_extended_kelvin_range: target.extended_kelvin_range
        )}

      {:error, reason} ->
        {:noreply, assign(socket, status: "ERROR #{type} #{id}: #{format_reason(reason)}")}
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

  @impl true
  def render(assigns), do: control_live(assigns)

  defp dispatch_action(socket, "light", id, {:brightness, level}) do
    with {:ok, light} <- fetch_light(id),
         {:ok, parsed} <- parse_level(level),
         :ok <- Control.Light.set_brightness(light, parsed) do
      State.put(:light, light.id, %{brightness: parsed})

      socket
      |> assign(:light_state, Map.update(socket.assigns.light_state, light.id, %{brightness: parsed}, &merge_state(&1, %{brightness: parsed})))
      |> assign(status: "BRIGHTNESS light #{light.name} -> #{parsed}%")
    else
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, {:color_temp, kelvin}) do
    with {:ok, light} <- fetch_light(id),
         {:ok, parsed} <- parse_kelvin(kelvin),
         :ok <- Control.Light.set_color_temp(light, parsed) do
      State.put(:light, light.id, %{kelvin: parsed})

      socket
      |> assign(:light_state, Map.update(socket.assigns.light_state, light.id, %{kelvin: parsed}, &merge_state(&1, %{kelvin: parsed})))
      |> assign(status: "TEMP light #{light.name} -> #{parsed}K")
    else
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:brightness, level}) do
    with {:ok, group} <- fetch_group(id),
         {:ok, parsed} <- parse_level(level),
         :ok <- Control.Group.set_brightness(group, parsed) do
      State.put(:group, group.id, %{brightness: parsed})

      socket
      |> assign(:group_state, Map.update(socket.assigns.group_state, group.id, %{brightness: parsed}, &merge_state(&1, %{brightness: parsed})))
      |> assign(status: "BRIGHTNESS group #{group.name} -> #{parsed}%")
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:color_temp, kelvin}) do
    with {:ok, group} <- fetch_group(id),
         {:ok, parsed} <- parse_kelvin(kelvin),
         :ok <- Control.Group.set_color_temp(group, parsed) do
      State.put(:group, group.id, %{kelvin: parsed})

      socket
      |> assign(:group_state, Map.update(socket.assigns.group_state, group.id, %{kelvin: parsed}, &merge_state(&1, %{kelvin: parsed})))
      |> assign(status: "TEMP group #{group.name} -> #{parsed}K")
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{format_reason(reason)}")
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
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{format_reason(reason)}")
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
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{format_reason(reason)}")
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
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{format_reason(reason)}")
    end
  end

  defp dispatch_toggle(socket, "group", id) do
    with {:ok, group} <- fetch_group(id) do
      action = toggle_action(socket.assigns.group_state, group.id)
      dispatch_action(socket, "group", id, action)
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{format_reason(reason)}")
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
        |> update_entity_list(type, updated)
        |> close_edit_modal()
        |> assign(status: "Saved #{type} #{updated.name}")

      {:ok, socket}
    else
      {:error, reason} ->
        {:error, "ERROR #{type} #{id}: #{format_reason(reason)}", socket}
    end
  end

  defp apply_display_name("light", light, attrs), do: Lights.update_display_name(light, attrs)
  defp apply_display_name("group", group, attrs), do: Groups.update_display_name(group, attrs)
  defp apply_display_name(_type, _target, _attrs), do: {:error, :invalid_type}

  defp update_entity_list(socket, "light", updated) do
    lights = Enum.map(socket.assigns.lights, &replace_entity(&1, updated))
    assign(socket, lights: lights)
  end

  defp update_entity_list(socket, "group", updated) do
    groups = Enum.map(socket.assigns.groups, &replace_entity(&1, updated))
    assign(socket, groups: groups)
  end

  defp update_entity_list(socket, _type, _updated), do: socket

  defp replace_entity(%{id: id} = _entity, %{id: id} = updated), do: updated
  defp replace_entity(entity, _updated), do: entity

  defp close_edit_modal(socket) do
    assign(socket,
      edit_modal_open: false,
      edit_target_type: nil,
      edit_target_id: nil,
      edit_name: nil,
      edit_display_name: "",
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
      edit_enabled: parse_optional_bool(Map.get(params, "enabled", socket.assigns.edit_enabled)),
      edit_extended_kelvin_range:
        parse_optional_bool(
          Map.get(params, "extended_kelvin_range", socket.assigns.edit_extended_kelvin_range)
        )
    )
  end

  defp normalize_edit_attrs(params) do
    [
      display_name: Map.get(params, "display_name"),
      actual_min_kelvin: parse_optional_integer(Map.get(params, "actual_min_kelvin")),
      actual_max_kelvin: parse_optional_integer(Map.get(params, "actual_max_kelvin")),
      extended_kelvin_range: parse_optional_bool(Map.get(params, "extended_kelvin_range")),
      enabled: parse_optional_bool(Map.get(params, "enabled"))
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp parse_optional_integer(nil), do: nil

  defp parse_optional_integer(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      nil
    else
      case Integer.parse(value) do
        {int, ""} -> int
        _ -> nil
      end
    end
  end

  defp parse_optional_integer(value) when is_integer(value), do: value
  defp parse_optional_integer(_value), do: nil

  defp format_kelvin(nil), do: ""
  defp format_kelvin(value) when is_integer(value), do: Integer.to_string(value)
  defp format_kelvin(_value), do: ""

  defp parse_optional_bool(nil), do: nil
  defp parse_optional_bool(value) when value in ["true", "false"], do: value == "true"
  defp parse_optional_bool(value) when is_boolean(value), do: value
  defp parse_optional_bool(_value), do: nil

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

  defp parse_level(level) when is_binary(level) do
    case Integer.parse(level) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_level}
    end
  end

  defp parse_level(level) when is_integer(level), do: {:ok, level}
  defp parse_level(_level), do: {:error, :invalid_level}

  defp parse_kelvin(kelvin) when is_binary(kelvin) do
    case Integer.parse(kelvin) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_kelvin}
    end
  end

  defp parse_kelvin(kelvin) when is_integer(kelvin), do: {:ok, kelvin}
  defp parse_kelvin(_kelvin), do: {:error, :invalid_kelvin}

  defp action_label(:on), do: "ON"
  defp action_label(:off), do: "OFF"
  defp action_label(_action), do: "ACTION"

  defp format_reason(reason), do: inspect(reason)

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

  defp filter_entities(entities, filter, show_disabled) do
    entities
    |> filter_by_source(filter)
    |> filter_by_enabled(show_disabled)
  end

  defp filter_by_source(entities, "all"), do: entities
  defp filter_by_source(entities, filter) when is_binary(filter) do
    case parse_source_filter(filter) do
      {:ok, source} -> Enum.filter(entities, &(&1.source == source))
      :error -> entities
    end
  end

  defp filter_by_source(entities, _filter), do: entities

  defp filter_by_enabled(entities, true), do: entities
  defp filter_by_enabled(entities, _show_disabled) do
    Enum.filter(entities, &(&1.enabled != false))
  end

  defp parse_source_filter("hue"), do: {:ok, :hue}
  defp parse_source_filter("ha"), do: {:ok, :ha}
  defp parse_source_filter("caseta"), do: {:ok, :caseta}
  defp parse_source_filter(_), do: :error

  defp parse_filter(filter) when filter in ["hue", "ha", "caseta"], do: filter
  defp parse_filter(_filter), do: "all"

  defp push_filter_patch(socket, updates) do
    updates = Map.new(updates)
    group_filter = Map.get(updates, :group_filter, socket.assigns.group_filter)
    light_filter = Map.get(updates, :light_filter, socket.assigns.light_filter)

    socket
    |> assign(updates)
    |> push_patch(to: "/?group_filter=#{group_filter}&light_filter=#{light_filter}")
  end
end
