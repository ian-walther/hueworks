defmodule HueworksWeb.SceneBuilderComponent do
  use Phoenix.LiveComponent

  alias HueworksWeb.SceneBuilderComponent.Flow
  alias HueworksWeb.SceneBuilderComponent.State

  def mount(socket) do
    {:ok,
     assign(socket,
       components: [State.blank_component()],
       room_lights: [],
       groups: [],
       light_states: [],
       scene_id: nil,
       builder: nil
     )}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    socket = assign(socket, Flow.initialize(socket.assigns))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="hw-scene-builder" id={@id}>
      <div class="hw-panel-header">
        <h4>Scene Components</h4>
        <button type="button" class="hw-button" phx-click="add_component" phx-target={@myself}>
          Add Component
        </button>
      </div>

      <%= for component <- @components do %>
        <div class="hw-card">
          <div class="hw-row">
            <div class="hw-row-title"><%= component.name %></div>
            <button
              type="button"
              class="hw-edit-button hw-delete-button"
              phx-click="remove_component"
              phx-target={@myself}
              phx-value-component_id={component.id}
              aria-label="Remove component"
            >
              ×
            </button>
          </div>

          <div class="hw-row">
            <label class="hw-modal-label">Light state</label>
            <form phx-change="select_light_state" phx-target={@myself} data-component-id={component.id}>
              <input type="hidden" name="component_id" value={component.id} />
              <select class="hw-select" name="light_state_id">
                <option value="" selected={is_nil(selected_state_value(component))}>Select light state</option>
                <option value="custom" selected={selected_state_value(component) == "custom"}>Custom</option>
                <option value="custom_color" selected={selected_state_value(component) == "custom_color"}>
                  Custom Color
                </option>
                <%= for state <- @light_states do %>
                  <option value={state.id} selected={to_string(state.id) == selected_state_value(component)}>
                    <%= state_option_label(state) %>
                  </option>
                <% end %>
              </select>
            </form>
            <%= if @light_states == [] do %>
              <p class="hw-muted">Create light states from Config before saving this scene.</p>
            <% end %>
          </div>

          <%= if custom_manual?(component) do %>
            <form phx-change="update_embedded_manual_config" phx-target={@myself} data-component-id={component.id}>
              <input type="hidden" name="component_id" value={component.id} />
              <input type="hidden" name="mode" value="temperature" />

              <div class="hw-row">
                <label class="hw-modal-label">Brightness</label>
                <span class="hw-slider-value"><%= custom_field_value(component, :brightness) %>%</span>
              </div>
              <input
                type="range"
                name="brightness"
                class="hw-modal-input"
                min="1"
                max="100"
                value={custom_field_value(component, :brightness)}
              />

              <div class="hw-row">
                <label class="hw-modal-label">Temperature</label>
                <span class="hw-slider-value"><%= custom_field_value(component, :kelvin) %>K</span>
              </div>
              <input
                type="range"
                name="temperature"
                class="hw-modal-input"
                min="1000"
                max="10000"
                value={custom_field_value(component, :kelvin)}
              />
            </form>
          <% end %>

          <%= if custom_color?(component) do %>
            <form phx-change="update_embedded_manual_config" phx-target={@myself} data-component-id={component.id}>
              <input type="hidden" name="component_id" value={component.id} />
              <input type="hidden" name="mode" value="color" />

              <div class="hw-row">
                <label class="hw-modal-label">Brightness</label>
                <span class="hw-slider-value"><%= custom_field_value(component, :brightness) %>%</span>
              </div>
              <input
                type="range"
                name="brightness"
                class="hw-modal-input"
                min="1"
                max="100"
                value={custom_field_value(component, :brightness)}
              />

              <div class="hw-color-preview">
                <span class="hw-color-swatch" style={custom_color_preview_style(component)}></span>
                <span class="hw-muted"><%= custom_color_preview_label(component) %></span>
              </div>

              <div class="hw-row">
                <label class="hw-modal-label">Hue</label>
                <span class="hw-slider-value"><%= custom_field_value(component, :hue) %>°</span>
              </div>
              <input
                type="range"
                name="hue"
                class="hw-modal-input"
                min="0"
                max="360"
                value={custom_field_value(component, :hue)}
              />
              <div class="hw-color-scale hw-hue-scale" aria-hidden="true"></div>

              <div class="hw-row">
                <label class="hw-modal-label">Saturation</label>
                <span class="hw-slider-value"><%= custom_field_value(component, :saturation) %>%</span>
              </div>
              <input
                type="range"
                name="saturation"
                class="hw-modal-input"
                min="0"
                max="100"
                value={custom_field_value(component, :saturation)}
              />
              <div class="hw-color-scale" style={custom_saturation_scale_style(component)} aria-hidden="true"></div>
            </form>
          <% end %>

          <%= if @builder.available_lights != [] do %>
            <div class="hw-row">
              <label class="hw-modal-label">Add light</label>
              <form phx-change="select_light" phx-target={@myself} data-component-id={component.id}>
                <input type="hidden" name="component_id" value={component.id} />
                <select class="hw-select" name="light_id">
                  <option value="">Select light</option>
                  <%= for light <- @builder.available_lights do %>
                    <option value={light.id}><%= display_name(light) %></option>
                  <% end %>
                </select>
              </form>
            </div>
          <% end %>

          <%= if @builder.available_groups != [] do %>
            <div class="hw-row">
              <label class="hw-modal-label">Add group</label>
              <form phx-change="select_group" phx-target={@myself} data-component-id={component.id}>
                <input type="hidden" name="component_id" value={component.id} />
                <select class="hw-select" name="group_id">
                  <option value="">Select group</option>
                  <%= for group <- @builder.available_groups do %>
                    <option value={group.id}><%= display_name(group) %></option>
                  <% end %>
                </select>
              </form>
            </div>
          <% end %>

          <% active_groups = component_groups(component, @groups, @builder.room_light_ids) %>
          <%= if active_groups != [] do %>
            <div class="hw-room-list">
              <%= for group <- active_groups do %>
                <span class="hw-room-item hw-room-item-row">
                  <span>
                    <%= display_name(group) %>
                    <span class="hw-muted">
                      (<%= Enum.count(component_group_light_ids(component, group, @builder.room_light_ids)) %> lights)
                    </span>
                  </span>
                  <button
                    type="button"
                    class="hw-button"
                    phx-click="toggle_group_default_power"
                    phx-target={@myself}
                    phx-value-component_id={component.id}
                    phx-value-group_id={group.id}
                  >
                    <%= "Power policy: #{power_policy_label(group_default_power(component, group, @builder.room_light_ids))}" %>
                  </button>
                  <button
                    type="button"
                    class="hw-edit-button hw-delete-button"
                    phx-click="remove_group"
                    phx-target={@myself}
                    phx-value-component_id={component.id}
                    phx-value-group_id={group.id}
                  >
                    ×
                  </button>
                </span>
              <% end %>
            </div>
          <% end %>

          <div class="hw-room-list">
            <%= for light_id <- component.light_ids do %>
              <span class="hw-room-item hw-room-item-row">
                <span><%= light_name(@room_lights, light_id) %></span>
                <button
                  type="button"
                  class="hw-button"
                  phx-click="toggle_light_default_power"
                  phx-target={@myself}
                  phx-value-component_id={component.id}
                  phx-value-light_id={light_id}
                >
                  <%= "Power policy: #{power_policy_label(light_default_power(component, light_id))}" %>
                </button>
                <button
                  type="button"
                  class="hw-edit-button hw-delete-button"
                  phx-click="remove_light"
                  phx-target={@myself}
                  phx-value-component_id={component.id}
                  phx-value-light_id={light_id}
                >
                  ×
                </button>
              </span>
            <% end %>
            <%= if component.light_ids == [] do %>
              <span class="hw-room-item hw-room-empty">No lights assigned</span>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="hw-scene-validation">
        <%= if @builder.unassigned_light_ids != [] do %>
          <p class="hw-error">
            Unassigned lights: <%= Enum.count(@builder.unassigned_light_ids) %>
          </p>
        <% end %>

        <%= if @builder.duplicate_light_ids != [] do %>
          <p class="hw-error">
            Duplicate lights assigned: <%= Enum.join(@builder.duplicate_light_ids, ", ") %>
          </p>
        <% end %>

        <%= if @builder.valid? do %>
          <p class="hw-muted">All lights assigned.</p>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("add_component", _params, socket) do
    socket =
      socket.assigns
      |> Flow.add_component()
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event("select_light", %{"component_id" => id, "light_id" => light_id}, socket) do
    socket =
      socket.assigns
      |> Flow.select_light(id, light_id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event("select_group", %{"component_id" => id, "group_id" => group_id}, socket) do
    socket =
      socket.assigns
      |> Flow.select_group(id, group_id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event(
        "select_light_state",
        %{"component_id" => id, "light_state_id" => state_id},
        socket
      ) do
    socket =
      socket.assigns
      |> Flow.select_light_state(id, state_id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event("update_embedded_manual_config", %{"component_id" => id} = params, socket) do
    socket =
      socket.assigns
      |> Flow.update_embedded_manual_config(id, params)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event("remove_light", %{"component_id" => id, "light_id" => light_id}, socket) do
    socket =
      socket.assigns
      |> Flow.remove_light(id, light_id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event("remove_group", %{"component_id" => id, "group_id" => group_id}, socket) do
    socket =
      socket.assigns
      |> Flow.remove_group(id, group_id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event("remove_component", %{"component_id" => id}, socket) do
    socket =
      socket.assigns
      |> Flow.remove_component(id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event(
        "toggle_light_default_power",
        %{"component_id" => component_id, "light_id" => light_id},
        socket
      ) do
    socket =
      socket.assigns
      |> Flow.toggle_light_default_power(component_id, light_id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  def handle_event(
        "toggle_group_default_power",
        %{"component_id" => component_id, "group_id" => group_id},
        socket
      ) do
    socket =
      socket.assigns
      |> Flow.toggle_group_default_power(component_id, group_id)
      |> apply_component_change(socket)

    {:noreply, socket}
  end

  defp notify_parent(socket) do
    send(self(), {:scene_builder_updated, socket.assigns.components, socket.assigns.builder})
  end

  defp apply_component_change(changes, socket) do
    socket =
      socket
      |> assign(changes)

    notify_parent(socket)
    socket
  end

  defp light_name(lights, id), do: State.light_name(lights, id)

  defp light_default_power(component, light_id),
    do: State.light_default_power(component, light_id)

  defp component_groups(component, groups, room_light_ids),
    do: State.component_groups(component, groups, room_light_ids)

  defp component_group_light_ids(component, group, room_light_ids),
    do: State.component_group_light_ids(component, group, room_light_ids)

  defp group_default_power(component, group, room_light_ids),
    do: State.group_default_power(component, group, room_light_ids)

  defp display_name(entity), do: State.display_name(entity)

  defp selected_state_value(component), do: State.selected_state_value(component)
  defp custom_manual?(component), do: State.custom_manual?(component)
  defp custom_color?(component), do: State.custom_color?(component)
  defp custom_field_value(component, key), do: State.custom_field_value(component, key)
  defp custom_color_preview_style(component), do: State.custom_color_preview_style(component)
  defp custom_color_preview_label(component), do: State.custom_color_preview_label(component)
  defp custom_saturation_scale_style(component), do: State.custom_saturation_scale_style(component)

  defp state_option_label(state), do: State.state_option_label(state)

  defp power_policy_label(policy), do: State.power_policy_label(policy)
end
