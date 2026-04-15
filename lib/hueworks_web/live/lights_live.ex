defmodule HueworksWeb.LightsLive do
  use Phoenix.LiveView

  alias Hueworks.Control.State
  alias Hueworks.Color
  alias Hueworks.Groups
  alias Hueworks.Lights.ManualControl
  alias HueworksWeb.FilterPrefs
  alias HueworksWeb.LightsLive.DisplayState
  alias HueworksWeb.LightsLive.Editor
  alias HueworksWeb.LightsLive.Entities
  alias HueworksWeb.LightsLive.Loader
  alias Hueworks.Util

  @impl true
  def mount(params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
      Phoenix.PubSub.subscribe(Hueworks.PubSub, Hueworks.ActiveScenes.topic())
    end

    filter_session_id = session["filter_session_id"]

    {:ok,
     assign(
       socket,
       Loader.mount_assigns(params, filter_session_id)
       |> Map.merge(Editor.default_assigns())
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
    case Editor.open_assigns(type, id) do
      {:ok, modal_assigns} ->
        {:noreply, assign(socket, modal_assigns)}

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
    {:noreply,
     assign(socket, Editor.update_assigns(socket.assigns, %{"display_name" => display_name}))}
  end

  def handle_event("save_display_name", %{"display_name" => display_name}, socket) do
    case save_edit(socket, %{"display_name" => display_name}) do
      {:ok, socket} -> {:noreply, socket}
      {:error, reason, socket} -> {:noreply, assign(socket, status: reason)}
    end
  end

  def handle_event("update_edit_fields", params, socket) do
    {:noreply, assign(socket, Editor.update_assigns(socket.assigns, params))}
  end

  def handle_event("save_edit_fields", params, socket) do
    case save_edit(socket, params) do
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

  def handle_event(
        "set_color",
        %{"type" => type, "id" => id, "hue" => hue, "saturation" => saturation},
        socket
      ) do
    {:noreply, dispatch_action(socket, type, id, {:color, hue, saturation})}
  end

  @impl true
  def handle_info({:active_scene_updated, room_id, scene_id}, socket) do
    {:noreply,
     assign(
       socket,
       :active_scene_by_room,
       put_active_scene(socket.assigns.active_scene_by_room, room_id, scene_id)
     )}
  end

  @impl true
  def handle_info({:control_state, :light, id, state}, socket) do
    replaced_state =
      socket.assigns.light_state
      |> Map.get(id, %{})
      |> DisplayState.replace_light(light_for_id(socket.assigns.lights, id), state)

    {:noreply,
     socket
     |> assign(:light_state, Map.put(socket.assigns.light_state, id, replaced_state))}
  end

  @impl true
  def handle_info({:control_state, :group, id, state}, socket) do
    {:noreply,
     socket
     |> assign(
       :group_state,
       Map.update(socket.assigns.group_state, id, state, &DisplayState.replace(&1, state))
     )}
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  defp dispatch_action(socket, "light", id, {:brightness, level}) do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, parsed} <- Util.parse_level(level),
         {:ok, _diff} <-
           ManualControl.apply_updates(light.room_id, [light.id], %{brightness: parsed}) do
      socket
      |> update_light_state_assign(light.id, %{brightness: parsed})
      |> assign(status: "BRIGHTNESS light #{Util.display_name(light)} -> #{parsed}%")
    else
      {:error, :scene_active_manual_adjustment_not_allowed} ->
        assign(socket, status: scene_active_manual_adjustment_message())

      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, {:color_temp, kelvin}) do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         {:ok, _diff} <- ManualControl.apply_updates(light.room_id, [light.id], %{kelvin: parsed}) do
      socket
      |> update_light_state_assign(light.id, %{kelvin: parsed})
      |> assign(status: "TEMP light #{Util.display_name(light)} -> #{parsed}K")
    else
      {:error, :scene_active_manual_adjustment_not_allowed} ->
        assign(socket, status: scene_active_manual_adjustment_message())

      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:brightness, level}) do
    with {:ok, group} <- Entities.fetch_group(id),
         {:ok, parsed} <- Util.parse_level(level),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <-
           ManualControl.apply_updates(group.room_id, light_ids, %{brightness: parsed}) do
      socket
      |> update_group_state_assign(group.id, %{brightness: parsed})
      |> assign(status: "BRIGHTNESS group #{Util.display_name(group)} -> #{parsed}%")
    else
      [] ->
        assign(socket, status: "ERROR group #{id}: no_members")

      {:error, :scene_active_manual_adjustment_not_allowed} ->
        assign(socket, status: scene_active_manual_adjustment_message())

      {:error, reason} ->
        assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:color_temp, kelvin}) do
    with {:ok, group} <- Entities.fetch_group(id),
         {:ok, parsed} <- Util.parse_kelvin(kelvin),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <- ManualControl.apply_updates(group.room_id, light_ids, %{kelvin: parsed}) do
      socket
      |> update_group_state_assign(group.id, %{kelvin: parsed})
      |> assign(status: "TEMP group #{Util.display_name(group)} -> #{parsed}K")
    else
      [] ->
        assign(socket, status: "ERROR group #{id}: no_members")

      {:error, :scene_active_manual_adjustment_not_allowed} ->
        assign(socket, status: scene_active_manual_adjustment_message())

      {:error, reason} ->
        assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, {:color, hue, saturation}) do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, parsed_hue, parsed_saturation, x, y} <- parse_color(hue, saturation),
         {:ok, _diff} <-
           ManualControl.apply_updates(light.room_id, [light.id], %{power: :on, x: x, y: y}) do
      socket
      |> update_light_state_assign(light.id, %{
        power: :on,
        x: x,
        y: y,
        kelvin: nil,
        temperature: nil
      })
      |> assign(
        status:
          "COLOR light #{Util.display_name(light)} -> #{parsed_hue}° / #{parsed_saturation}%"
      )
    else
      {:error, :scene_active_manual_adjustment_not_allowed} ->
        assign(socket, status: scene_active_manual_adjustment_message())

      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:color, hue, saturation}) do
    with {:ok, group} <- Entities.fetch_group(id),
         {:ok, parsed_hue, parsed_saturation, x, y} <- parse_color(hue, saturation),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, _diff} <-
           ManualControl.apply_updates(group.room_id, light_ids, %{power: :on, x: x, y: y}) do
      socket
      |> update_group_state_assign(group.id, %{
        power: :on,
        x: x,
        y: y,
        kelvin: nil,
        temperature: nil
      })
      |> assign(
        status:
          "COLOR group #{Util.display_name(group)} -> #{parsed_hue}° / #{parsed_saturation}%"
      )
    else
      [] ->
        assign(socket, status: "ERROR group #{id}: no_members")

      {:error, :scene_active_manual_adjustment_not_allowed} ->
        assign(socket, status: scene_active_manual_adjustment_message())

      {:error, reason} ->
        assign(socket, status: "ERROR group #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, action) do
    with {:ok, light} <- Entities.fetch_light(id),
         {:ok, updated_attrs} <-
           ManualControl.apply_power_action(light.room_id, [light.id], action) do
      socket
      |> update_light_state_assign(light.id, updated_attrs)
      |> assign(status: "#{action_label(action)} light #{Util.display_name(light)}")
    else
      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, action) do
    with {:ok, group} <- Entities.fetch_group(id),
         light_ids when light_ids != [] <- group_light_ids(group.id),
         {:ok, updated_attrs} <-
           ManualControl.apply_power_action(group.room_id, light_ids, action) do
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
    with {:ok, light} <- Entities.fetch_light(id) do
      action = toggle_action(socket.assigns.light_state, light.id)
      dispatch_action(socket, "light", id, action)
    else
      {:error, reason} ->
        assign(socket, status: "ERROR light #{id}: #{Util.format_reason(reason)}")
    end
  end

  defp dispatch_toggle(socket, "group", id) do
    with {:ok, group} <- Entities.fetch_group(id) do
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

  defp save_edit(socket, params) do
    type = socket.assigns.edit_target_type
    id = socket.assigns.edit_target_id

    with {:ok, updated} <- Editor.save(type, id, params) do
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

  defp reload_entities(socket) do
    assign(socket, Loader.reload_assigns(socket.assigns))
  end

  defp close_edit_modal(socket) do
    assign(socket, Editor.default_assigns())
  end

  defp group_light_ids(group_id) when is_integer(group_id) do
    Groups.member_light_ids(group_id)
  end

  defp action_label(:on), do: "ON"
  defp action_label(:off), do: "OFF"
  defp action_label(_action), do: "ACTION"

  defp light_for_id(lights, id) do
    Enum.find(lights, &(&1.id == id))
  end

  defp update_light_state_assign(socket, light_id, attrs)
       when is_integer(light_id) and is_map(attrs) do
    assign(
      socket,
      :light_state,
      Map.update(socket.assigns.light_state, light_id, attrs, &DisplayState.merge(&1, attrs))
    )
  end

  defp update_group_state_assign(socket, group_id, attrs)
       when is_integer(group_id) and is_map(attrs) do
    assign(
      socket,
      :group_state,
      Map.update(socket.assigns.group_state, group_id, attrs, &DisplayState.merge(&1, attrs))
    )
  end

  defp get_state_value(state_map, id, key, fallback) do
    state_map
    |> Map.get(id, %{})
    |> Map.get(key, fallback)
  end

  defp manual_adjustment_locked?(active_scene_by_room, room_id)
       when is_map(active_scene_by_room) do
    is_integer(room_id) and Map.has_key?(active_scene_by_room, room_id)
  end

  defp manual_adjustment_locked?(_active_scene_by_room, _room_id), do: false

  defp scene_active_manual_adjustment_message do
    "Brightness, temperature, and color are read-only while a scene is active. Deactivate the scene to adjust them manually."
  end

  defp color_preview_values(state_map, id) do
    state = Map.get(state_map, id, %{})

    {hue, saturation} =
      case Color.xy_to_hs(
             Map.get(state, :x),
             Map.get(state, :y)
           ) do
        {hue, saturation} -> {hue, saturation}
        nil -> {0, 100}
      end

    brightness =
      case get_state_value(state_map, id, :brightness, 100) do
        value when is_integer(value) -> value
        value when is_float(value) -> round(value)
        _ -> 100
      end

    %{hue: hue, saturation: saturation, brightness: brightness}
  end

  defp color_preview_style(state_map, id) do
    %{hue: hue, saturation: saturation, brightness: brightness} =
      color_preview_values(state_map, id)

    {r, g, b} = Color.hsb_to_rgb(hue, saturation, brightness) || {143, 177, 255}
    "background-color: rgb(#{r} #{g} #{b});"
  end

  defp color_preview_label(state_map, id) do
    %{hue: hue, saturation: saturation, brightness: brightness} =
      color_preview_values(state_map, id)

    "Color: #{hue}°, #{saturation}% saturation, #{brightness}% brightness"
  end

  defp color_saturation_scale_style(state_map, id) do
    %{hue: hue, brightness: brightness} = color_preview_values(state_map, id)
    {r1, g1, b1} = Color.hsb_to_rgb(hue, 0, brightness) || {255, 255, 255}
    {r2, g2, b2} = Color.hsb_to_rgb(hue, 100, brightness) || {255, 255, 255}
    "background: linear-gradient(90deg, rgb(#{r1} #{g1} #{b1}), rgb(#{r2} #{g2} #{b2}));"
  end

  defp parse_color(hue, saturation) do
    with parsed_hue when is_integer(parsed_hue) <- Util.normalize_hue_degrees(hue),
         parsed_saturation when is_integer(parsed_saturation) <-
           Util.normalize_saturation(saturation),
         {x, y} when is_number(x) and is_number(y) <-
           Color.hs_to_xy(parsed_hue, parsed_saturation) do
      {:ok, parsed_hue, parsed_saturation, x, y}
    else
      _ -> {:error, :invalid_color}
    end
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

  defp put_active_scene(active_scene_by_room, room_id, scene_id) do
    active_scene_by_room = active_scene_by_room || %{}

    case scene_id do
      scene_id when is_integer(scene_id) -> Map.put(active_scene_by_room, room_id, scene_id)
      _ -> Map.delete(active_scene_by_room, room_id)
    end
  end
end
