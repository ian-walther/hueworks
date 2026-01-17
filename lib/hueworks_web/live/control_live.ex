defmodule HueworksWeb.ControlLive do
  use Phoenix.LiveView

  alias Hueworks.Control
  alias Hueworks.Groups
  alias Hueworks.Lights

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       groups: Groups.list_controllable_groups(),
       lights: Lights.list_controllable_lights(),
       group_filter: "all",
       light_filter: "all",
       status: nil
     )}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply,
     assign(socket,
       groups: Groups.list_controllable_groups(),
       lights: Lights.list_controllable_lights(),
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

  def render(assigns) do
    ~H"""
    <div class="hw-shell">
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
                    <input
                      id={"group-level-#{group.id}"}
                      type="range"
                      min="1"
                      max="100"
                      value="75"
                      phx-hook="BrightnessSlider"
                      data-type="group"
                      data-id={group.id}
                    />
                    <span id={"group-brightness-label-#{group.id}"}>Brightness</span>
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
                    <input
                      id={"light-level-#{light.id}"}
                      type="range"
                      min="1"
                      max="100"
                      value="75"
                      phx-hook="BrightnessSlider"
                      data-type="light"
                      data-id={light.id}
                    />
                    <span id={"light-brightness-label-#{light.id}"}>Brightness</span>
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
      assign(socket, status: "BRIGHTNESS light #{light.name} -> #{parsed}%")
    else
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, {:brightness, level}) do
    with {:ok, group} <- fetch_group(id),
         {:ok, parsed} <- parse_level(level),
         :ok <- Control.Group.set_brightness(group, parsed) do
      assign(socket, status: "BRIGHTNESS group #{group.name} -> #{parsed}%")
    else
      {:error, reason} -> assign(socket, status: "ERROR group #{id}: #{format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "light", id, action) do
    with {:ok, light} <- fetch_light(id),
         :ok <- apply_light_action(light, action) do
      assign(socket, status: "#{action_label(action)} light #{light.name}")
    else
      {:error, reason} -> assign(socket, status: "ERROR light #{id}: #{format_reason(reason)}")
    end
  end

  defp dispatch_action(socket, "group", id, action) do
    with {:ok, group} <- fetch_group(id),
         :ok <- apply_group_action(group, action) do
      assign(socket, status: "#{action_label(action)} group #{group.name}")
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

  defp action_label(:on), do: "ON"
  defp action_label(:off), do: "OFF"
  defp action_label(_action), do: "ACTION"

  defp format_reason(reason), do: inspect(reason)

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
