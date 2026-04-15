defmodule HueworksWeb.SceneBuilderComponent do
  use Phoenix.LiveComponent

  alias Hueworks.Scenes.Builder
  alias Hueworks.Util
  alias HueworksWeb.SceneBuilderComponent.State

  def mount(socket) do
    {:ok,
     assign(socket,
       components: [State.blank_component()],
       room_lights: [],
       groups: [],
       light_states: [],
       scene_id: nil,
       builder: nil,
       selections: %{}
     )}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> normalize_components()
      |> refresh_builder()

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
                <option value="" selected={is_nil(selected_state_id(component))}>Select light state</option>
                <%= for state <- @light_states do %>
                  <option value={state.id} selected={to_string(state.id) == to_string(component.light_state_id)}>
                    <%= state_option_label(state) %>
                  </option>
                <% end %>
              </select>
            </form>
            <%= if @light_states == [] do %>
              <p class="hw-muted">Create light states from Config before saving this scene.</p>
            <% end %>
          </div>

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
              <button
                type="button"
                class="hw-button"
                phx-click="add_light"
                phx-target={@myself}
                phx-value-component_id={component.id}
              >
                Add
              </button>
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
              <button
                type="button"
                class="hw-button"
                phx-click="add_group"
                phx-target={@myself}
                phx-value-component_id={component.id}
              >
                Add
              </button>
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
    next_id =
      socket.assigns.components
      |> State.add_component()

    socket = refresh_builder(assign(socket, components: next_id))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("select_light", %{"component_id" => id, "light_id" => light_id}, socket) do
    selections = State.select_light(socket.assigns[:selections], id, light_id)

    {:noreply, assign(socket, selections: selections)}
  end

  def handle_event("select_group", %{"component_id" => id, "group_id" => group_id}, socket) do
    selections = State.select_group(socket.assigns[:selections], id, group_id)

    {:noreply, assign(socket, selections: selections)}
  end

  def handle_event(
        "select_light_state",
        %{"component_id" => id, "light_state_id" => state_id},
        socket
      ) do
    components =
      State.select_light_state(
        socket.assigns.components,
        id,
        state_id,
        socket.assigns.light_states
      )

    socket = socket |> assign(components: components) |> refresh_builder()
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("add_light", %{"component_id" => id}, socket) do
    component_id = Util.parse_id(id)
    light_id = Map.get(socket.assigns[:selections] || %{}, {:light, component_id})
    components = State.add_light(socket.assigns.components, id, light_id)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("add_group", %{"component_id" => id}, socket) do
    component_id = Util.parse_id(id)
    group_id = Map.get(socket.assigns[:selections] || %{}, {:group, component_id})
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))

    components =
      State.add_group(socket.assigns.components, id, group, socket.assigns.builder.room_light_ids)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("remove_light", %{"component_id" => id, "light_id" => light_id}, socket) do
    components = State.remove_light(socket.assigns.components, id, light_id)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("remove_component", %{"component_id" => id}, socket) do
    components = State.remove_component(socket.assigns.components, id)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event(
        "toggle_light_default_power",
        %{"component_id" => component_id, "light_id" => light_id},
        socket
      ) do
    components =
      State.toggle_light_default_power(socket.assigns.components, component_id, light_id)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event(
        "toggle_group_default_power",
        %{"component_id" => component_id, "group_id" => group_id},
        socket
      ) do
    group = Enum.find(socket.assigns.groups, &(&1.id == Util.parse_id(group_id)))

    components =
      State.toggle_group_default_power(
        socket.assigns.components,
        component_id,
        group,
        socket.assigns.builder.room_light_ids
      )

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  defp refresh_builder(socket) do
    builder =
      Builder.build(
        List.wrap(socket.assigns.room_lights),
        List.wrap(socket.assigns.groups),
        List.wrap(socket.assigns.components)
      )

    assign(socket, builder: builder)
  end

  defp notify_parent(socket) do
    send(self(), {:scene_builder_updated, socket.assigns.components, socket.assigns.builder})
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

  defp selected_state_id(component), do: State.selected_state_id(component)

  defp state_option_label(state), do: State.state_option_label(state)

  defp normalize_components(socket) do
    assign(
      socket,
      components:
        State.normalize_components(socket.assigns.components, socket.assigns.light_states)
    )
  end

  defp power_policy_label(policy), do: State.power_policy_label(policy)
end
