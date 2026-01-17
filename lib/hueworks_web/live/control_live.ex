defmodule HueworksWeb.ControlLive do
  use Phoenix.LiveView

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
    {group_levels, group_temps, group_power} = build_group_state(groups)
    {light_levels, light_temps, light_power} = build_light_state(lights)

    {:ok,
     assign(socket,
       groups: groups,
       lights: lights,
       group_filter: "all",
       light_filter: "all",
       group_levels: group_levels,
       group_temps: group_temps,
       group_power: group_power,
       light_levels: light_levels,
       light_temps: light_temps,
       light_power: light_power,
       status: nil
     )}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    State.bootstrap()
    groups = Groups.list_controllable_groups()
    lights = Lights.list_controllable_lights()
    {group_levels, group_temps, group_power} = build_group_state(groups)
    {light_levels, light_temps, light_power} = build_light_state(lights)

    {:noreply,
     assign(socket,
       groups: groups,
       lights: lights,
       group_levels: group_levels,
       group_temps: group_temps,
       group_power: group_power,
       light_levels: light_levels,
       light_temps: light_temps,
       light_power: light_power,
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
    current_kelvin = Map.get(socket.assigns.light_temps, id)
    current_power = Map.get(socket.assigns.light_power, id)
    socket =
      socket
      |> assign(:light_levels, Map.put(socket.assigns.light_levels, id, Map.get(state, :brightness, 75)))
      |> assign(:light_temps, Map.put(socket.assigns.light_temps, id, Map.get(state, :kelvin, current_kelvin)))
      |> assign(:light_power, Map.put(socket.assigns.light_power, id, Map.get(state, :power, current_power)))
      |> push_state_update(:light, id, state)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:control_state, :group, id, state}, socket) do
    current_kelvin = Map.get(socket.assigns.group_temps, id)
    current_power = Map.get(socket.assigns.group_power, id)
    socket =
      socket
      |> assign(:group_levels, Map.put(socket.assigns.group_levels, id, Map.get(state, :brightness, 75)))
      |> assign(:group_temps, Map.put(socket.assigns.group_temps, id, Map.get(state, :kelvin, current_kelvin)))
      |> assign(:group_power, Map.put(socket.assigns.group_power, id, Map.get(state, :power, current_power)))
      |> push_state_update(:group, id, state)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="hw-state-updater" class="hw-shell" phx-hook="StateUpdater">
      <div class="hw-topbar">
        <div>
          <h1 class="hw-title">HueWorks Control Console</h1>
          <p class="hw-subtitle">Minimal UI for live device testing and grouping logic.</p>
        </div>
        <div class="hw-actions">
          <button class="hw-button" phx-click="refresh">Reload</button>
        </div>
      </div>

      <%= if @status do %>
        <div class="hw-status"><%= @status %></div>
      <% end %>

      <div class="hw-grid">
        <section class="hw-panel">
          <div class="hw-panel-header">
            <h2>Groups</h2>
            <span class="hw-count"><%= length(filter_entities(@groups, @group_filter)) %></span>
          </div>
          <form class="hw-filter" phx-change="set_group_filter">
            <select name="group_filter" class="hw-select">
              <option value="all" selected={@group_filter == "all"}>All</option>
              <option value="hue" selected={@group_filter == "hue"}>Hue</option>
              <option value="ha" selected={@group_filter == "ha"}>HA</option>
              <option value="caseta" selected={@group_filter == "caseta"}>Caseta</option>
            </select>
          </form>
          <div class="hw-list">
            <%= for group <- filter_entities(@groups, @group_filter) do %>
              <div class="hw-card" id={"group-#{group.id}"}>
                <div class="hw-card-title">
                  <div>
                    <h3><%= group.name %></h3>
                    <p class="hw-meta">source: <%= group.source %></p>
                  </div>
                  <span class="hw-pill">group</span>
                </div>

                <div class="hw-controls">
                  <button class="hw-button hw-button-on" phx-click="toggle_on" phx-value-type="group" phx-value-id={group.id}>On</button>
                  <button class="hw-button hw-button-off" phx-click="toggle_off" phx-value-type="group" phx-value-id={group.id}>Off</button>
                  <div class="hw-slider">
                    <% brightness = Map.get(@group_levels, group.id, 75) %>
                    <input
                      id={"group-level-#{group.id}"}
                      type="range"
                      min="1"
                      max="100"
                      value={brightness}
                      phx-hook="BrightnessSlider"
                      data-type="group"
                      data-id={group.id}
                      data-output-id={"group-brightness-value-#{group.id}"}
                    />
                    <span id={"group-brightness-label-#{group.id}"}>Brightness</span>
                    <span id={"group-brightness-value-#{group.id}"} class="hw-slider-value">
                      <%= brightness %>%
                    </span>
                  </div>
                  <div class="hw-slider">
                    <% {min_k, max_k} = temp_range(group) %>
                    <% kelvin = Map.get(@group_temps, group.id, round((min_k + max_k) / 2)) %>
                    <input
                      id={"group-temp-#{group.id}"}
                      type="range"
                      min={min_k}
                      max={max_k}
                      value={kelvin}
                      phx-hook="TempSlider"
                      data-type="group"
                      data-id={group.id}
                      data-output-id={"group-temp-value-#{group.id}"}
                    />
                    <span id={"group-temp-label-#{group.id}"}>Temperature</span>
                    <span id={"group-temp-value-#{group.id}"} class="hw-slider-value">
                      <%= kelvin %>K
                    </span>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </section>

        <section class="hw-panel">
          <div class="hw-panel-header">
            <h2>Lights</h2>
            <span class="hw-count"><%= length(filter_entities(@lights, @light_filter)) %></span>
          </div>
          <form class="hw-filter" phx-change="set_light_filter">
            <select name="light_filter" class="hw-select">
              <option value="all" selected={@light_filter == "all"}>All</option>
              <option value="hue" selected={@light_filter == "hue"}>Hue</option>
              <option value="ha" selected={@light_filter == "ha"}>HA</option>
              <option value="caseta" selected={@light_filter == "caseta"}>Caseta</option>
            </select>
          </form>
          <div class="hw-list">
            <%= for light <- filter_entities(@lights, @light_filter) do %>
              <div class="hw-card" id={"light-#{light.id}"}>
                <div class="hw-card-title">
                  <div>
                    <h3><%= light.name %></h3>
                    <p class="hw-meta">source: <%= light.source %></p>
                  </div>
                  <span class="hw-pill"><%= light.source_id %></span>
                </div>

                <div class="hw-controls">
                  <button class="hw-button hw-button-on" phx-click="toggle_on" phx-value-type="light" phx-value-id={light.id}>On</button>
                  <button class="hw-button hw-button-off" phx-click="toggle_off" phx-value-type="light" phx-value-id={light.id}>Off</button>
                  <div class="hw-slider">
                    <% brightness = Map.get(@light_levels, light.id, 75) %>
                    <input
                      id={"light-level-#{light.id}"}
                      type="range"
                      min="1"
                      max="100"
                      value={brightness}
                      phx-hook="BrightnessSlider"
                      data-type="light"
                      data-id={light.id}
                      data-output-id={"light-brightness-value-#{light.id}"}
                    />
                    <span id={"light-brightness-label-#{light.id}"}>Brightness</span>
                    <span id={"light-brightness-value-#{light.id}"} class="hw-slider-value">
                      <%= brightness %>%
                    </span>
                  </div>
                  <div class="hw-slider">
                    <% {min_k, max_k} = temp_range(light) %>
                    <% kelvin = Map.get(@light_temps, light.id, round((min_k + max_k) / 2)) %>
                    <input
                      id={"light-temp-#{light.id}"}
                      type="range"
                      min={min_k}
                      max={max_k}
                      value={kelvin}
                      phx-hook="TempSlider"
                      data-type="light"
                      data-id={light.id}
                      data-output-id={"light-temp-value-#{light.id}"}
                    />
                    <span id={"light-temp-label-#{light.id}"}>Temperature</span>
                    <span id={"light-temp-value-#{light.id}"} class="hw-slider-value">
                      <%= kelvin %>K
                    </span>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp dispatch_action(socket, "light", id, {:brightness, level}) do
    with {:ok, light} <- fetch_light(id),
         {:ok, parsed} <- parse_level(level),
         :ok <- Control.Light.set_brightness(light, parsed) do
      State.put(:light, light.id, %{brightness: parsed})

      socket
      |> assign(:light_levels, Map.put(socket.assigns.light_levels, light.id, parsed))
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
      |> assign(:light_temps, Map.put(socket.assigns.light_temps, light.id, parsed))
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
      |> assign(:group_levels, Map.put(socket.assigns.group_levels, group.id, parsed))
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
      |> assign(:group_temps, Map.put(socket.assigns.group_temps, group.id, parsed))
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
      |> assign(:light_power, Map.put(socket.assigns.light_power, light.id, action))
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
      |> assign(:group_power, Map.put(socket.assigns.group_power, group.id, action))
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

  defp temp_range(entity) do
    min_kelvin = Map.get(entity, :min_kelvin) || Map.get(entity, "min_kelvin")
    max_kelvin = Map.get(entity, :max_kelvin) || Map.get(entity, "max_kelvin")

    cond do
      is_number(min_kelvin) and is_number(max_kelvin) ->
        {round(min_kelvin), round(max_kelvin)}

      true ->
        case mired_range(entity) do
          {min_mired, max_mired} when min_mired > 0 and max_mired > 0 ->
            min_k = round(1_000_000 / max_mired)
            max_k = round(1_000_000 / min_mired)
            {min_k, max_k}

          nil ->
            {2000, 6500}

          _ ->
            {2000, 6500}
        end
    end
  end

  defp push_state_update(socket, type, id, state) do
    payload = %{
      type: type,
      id: id,
      brightness: Map.get(state, :brightness),
      kelvin: Map.get(state, :kelvin),
      power: Map.get(state, :power)
    }

    push_event(socket, "control_state_update", payload)
  end

  defp build_group_state(groups) do
    Enum.reduce(groups, {%{}, %{}, %{}}, fn group, {levels, temps, power} ->
      {min_k, max_k} = temp_range(group)
      kelvin = round((min_k + max_k) / 2)

      state =
        State.ensure(:group, group.id, %{
          brightness: 75,
          kelvin: kelvin,
          power: :off
        })

      {
        Map.put(levels, group.id, Map.get(state, :brightness, 75)),
        Map.put(temps, group.id, Map.get(state, :kelvin, kelvin)),
        Map.put(power, group.id, Map.get(state, :power, :off))
      }
    end)
  end

  defp build_light_state(lights) do
    Enum.reduce(lights, {%{}, %{}, %{}}, fn light, {levels, temps, power} ->
      {min_k, max_k} = temp_range(light)
      kelvin = round((min_k + max_k) / 2)

      state =
        State.ensure(:light, light.id, %{
          brightness: 75,
          kelvin: kelvin,
          power: :off
        })

      {
        Map.put(levels, light.id, Map.get(state, :brightness, 75)),
        Map.put(temps, light.id, Map.get(state, :kelvin, kelvin)),
        Map.put(power, light.id, Map.get(state, :power, :off))
      }
    end)
  end

  defp mired_range(%{metadata: metadata}) when is_map(metadata) do
    capabilities = Map.get(metadata, "capabilities") || %{}
    control = get_nested(capabilities, "control") || %{}
    ct = get_nested(control, "ct") || %{}
    min_mired = get_nested(ct, "min")
    max_mired = get_nested(ct, "max")

    if is_number(min_mired) and is_number(max_mired) do
      {min_mired, max_mired}
    else
      nil
    end
  end

  defp mired_range(_entity), do: nil

  defp get_nested(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      try do
        Map.get(map, String.to_existing_atom(key))
      rescue
        ArgumentError -> nil
      end
  end

  defp get_nested(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key)
  end

  defp get_nested(_map, _key), do: nil

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
