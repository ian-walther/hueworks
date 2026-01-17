defmodule HueworksWeb.ControlLive do
  use Phoenix.LiveView

  alias Hueworks.Groups
  alias Hueworks.Lights

  def mount(_params, _session, socket) do
    {:ok, assign(socket, groups: Groups.list_controllable_groups(), lights: Lights.list_controllable_lights(), status: nil)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply,
     assign(socket,
       groups: Groups.list_controllable_groups(),
       lights: Lights.list_controllable_lights(),
       status: "Reloaded database snapshot"
     )}
  end

  def handle_event("toggle_on", %{"type" => type, "id" => id}, socket) do
    {:noreply, assign(socket, status: "ON #{type} #{id}")}
  end

  def handle_event("toggle_off", %{"type" => type, "id" => id}, socket) do
    {:noreply, assign(socket, status: "OFF #{type} #{id}")}
  end

  def handle_event("set_brightness", %{"type" => type, "id" => id, "level" => level}, socket) do
    {:noreply, assign(socket, status: "BRIGHTNESS #{type} #{id} -> #{level}%")}
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
            <span class="hw-count"><%= length(@groups) %></span>
          </div>
          <div class="hw-list">
            <%= for group <- @groups do %>
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
            <span class="hw-count"><%= length(@lights) %></span>
          </div>
          <div class="hw-list">
            <%= for light <- @lights do %>
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
end
