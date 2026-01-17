defmodule HueworksWeb.ControlLive do
  use Phoenix.LiveView

  import Phoenix.Component

  embed_templates "control_live/*"

  alias Hueworks.Control
  alias Hueworks.Control.State
  alias Hueworks.Groups
  alias Hueworks.Lights

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
    end

    groups = Groups.list_controllable_groups()
    lights = Lights.list_controllable_lights()
    group_state = build_group_state(groups)
    light_state = build_light_state(lights)

    {:ok,
     assign(socket,
       groups: groups,
       lights: lights,
       group_filter: "all",
       light_filter: "all",
       group_state: group_state,
       light_state: light_state,
       status: nil
     )}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    State.bootstrap()
    groups = Groups.list_controllable_groups()
    lights = Lights.list_controllable_lights()
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
    {:noreply, assign(socket, group_filter: filter)}
  end

  def handle_event("set_light_filter", %{"light_filter" => filter}, socket) do
    {:noreply, assign(socket, light_filter: filter)}
  end

  def handle_event("toggle_on", %{"type" => type, "id" => id}, socket) do
    {:noreply, dispatch_action(socket, type, id, :on)}
  end

  def handle_event("toggle_off", %{"type" => type, "id" => id}, socket) do
    {:noreply, dispatch_action(socket, type, id, :off)}
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
      {min_k, max_k} = Lights.temp_range(group)
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
      {min_k, max_k} = Lights.temp_range(light)
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

  defp filter_entities(entities, "all"), do: entities
  defp filter_entities(entities, filter) when is_binary(filter) do
    case parse_source_filter(filter) do
      {:ok, source} -> Enum.filter(entities, &(&1.source == source))
      :error -> entities
    end
  end

  defp filter_entities(entities, _filter), do: entities

  defp parse_source_filter("hue"), do: {:ok, :hue}
  defp parse_source_filter("ha"), do: {:ok, :ha}
  defp parse_source_filter("caseta"), do: {:ok, :caseta}
  defp parse_source_filter(_), do: :error
end
