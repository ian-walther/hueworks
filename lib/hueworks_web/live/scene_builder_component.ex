defmodule HueworksWeb.SceneBuilderComponent do
  use Phoenix.LiveComponent

  alias Hueworks.Scenes.Builder
  alias Hueworks.Schemas.LightState
  alias Hueworks.Util

  @blank_component %{
    id: 1,
    name: "Component 1",
    light_ids: [],
    group_ids: [],
    light_state_id: nil,
    light_defaults: %{}
  }

  def mount(socket) do
    {:ok,
     assign(socket,
       components: [@blank_component],
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
      |> normalize_component_light_defaults()
      |> normalize_component_light_states()
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
      |> Enum.map(& &1.id)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    components =
      socket.assigns.components ++
        [Map.put(@blank_component, :id, next_id) |> Map.put(:name, "Component #{next_id}")]

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("select_light", %{"component_id" => id, "light_id" => light_id}, socket) do
    selections =
      Map.put(socket.assigns[:selections] || %{}, {:light, parse_id(id)}, parse_id(light_id))

    {:noreply, assign(socket, selections: selections)}
  end

  def handle_event("select_group", %{"component_id" => id, "group_id" => group_id}, socket) do
    selections =
      Map.put(socket.assigns[:selections] || %{}, {:group, parse_id(id)}, parse_id(group_id))

    {:noreply, assign(socket, selections: selections)}
  end

  def handle_event(
        "select_light_state",
        %{"component_id" => id, "light_state_id" => state_id},
        socket
      ) do
    valid_ids =
      socket.assigns.light_states |> Enum.map(& &1.id) |> Enum.map(&to_string/1) |> MapSet.new()

    component_id = parse_id(id)
    normalized_state_id = normalize_light_state_id(state_id, valid_ids)

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == component_id do
          %{component | light_state_id: normalized_state_id}
        else
          component
        end
      end)

    socket = socket |> assign(components: components) |> refresh_builder()
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("add_light", %{"component_id" => id}, socket) do
    component_id = parse_id(id)
    light_id = Map.get(socket.assigns[:selections] || %{}, {:light, component_id})

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == component_id and is_integer(light_id) do
          defaults = component |> Map.get(:light_defaults, %{}) |> Map.put(light_id, :force_on)

          %{
            component
            | light_ids: Enum.uniq(component.light_ids ++ [light_id]),
              light_defaults: defaults
          }
        else
          component
        end
      end)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("add_group", %{"component_id" => id}, socket) do
    component_id = parse_id(id)
    group_id = Map.get(socket.assigns[:selections] || %{}, {:group, component_id})
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))
    room_light_ids = socket.assigns.builder.room_light_ids

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == component_id and group do
          group_light_ids = Builder.group_room_light_ids(group, room_light_ids)

          defaults =
            Enum.reduce(group_light_ids, Map.get(component, :light_defaults, %{}), fn light_id,
                                                                                      acc ->
              Map.put_new(acc, light_id, :force_on)
            end)

          %{
            component
            | light_ids: Enum.uniq(component.light_ids ++ group_light_ids),
              group_ids: Enum.uniq(component.group_ids ++ [group_id]),
              light_defaults: defaults
          }
        else
          component
        end
      end)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("remove_light", %{"component_id" => id, "light_id" => light_id}, socket) do
    component_id = parse_id(id)
    parsed_light_id = parse_id(light_id)

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == component_id do
          defaults = component |> Map.get(:light_defaults, %{}) |> Map.delete(parsed_light_id)

          %{
            component
            | light_ids: List.delete(component.light_ids, parsed_light_id),
              light_defaults: defaults
          }
        else
          component
        end
      end)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("remove_component", %{"component_id" => id}, socket) do
    components = socket.assigns.components |> Enum.reject(&(&1.id == parse_id(id)))
    components = if components == [], do: [@blank_component], else: components

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event(
        "toggle_light_default_power",
        %{"component_id" => component_id, "light_id" => light_id},
        socket
      ) do
    parsed_component_id = parse_id(component_id)
    parsed_light_id = parse_id(light_id)

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == parsed_component_id and is_integer(parsed_light_id) do
          defaults = Map.get(component, :light_defaults, %{})

          current =
            Map.get(defaults, parsed_light_id, :force_on) |> normalize_default_power_value()

          %{
            component
            | light_defaults: Map.put(defaults, parsed_light_id, next_power_policy(current))
          }
        else
          component
        end
      end)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event(
        "toggle_group_default_power",
        %{"component_id" => component_id, "group_id" => group_id},
        socket
      ) do
    parsed_component_id = parse_id(component_id)
    parsed_group_id = parse_id(group_id)
    room_light_ids = socket.assigns.builder.room_light_ids

    components =
      Enum.map(socket.assigns.components, fn component ->
        group = Enum.find(socket.assigns.groups, &(&1.id == parsed_group_id))

        if component.id == parsed_component_id and group do
          group_light_ids = component_group_light_ids(component, group, room_light_ids)
          current = group_default_power(component, group, room_light_ids)
          next = next_power_policy(current)
          defaults = Map.get(component, :light_defaults, %{})

          updated_defaults =
            Enum.reduce(group_light_ids, defaults, fn light_id, acc ->
              Map.put(acc, light_id, next)
            end)

          %{component | light_defaults: updated_defaults}
        else
          component
        end
      end)

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

  defp light_name(lights, id) do
    case Enum.find(lights, &(&1.id == id)) do
      nil -> "Light #{id}"
      light -> display_name(light)
    end
  end

  defp light_default_power(component, light_id) do
    component
    |> Map.get(:light_defaults, %{})
    |> Map.get(light_id, :force_on)
    |> normalize_default_power_value()
  end

  defp component_groups(component, groups, room_light_ids) do
    component_light_ids = MapSet.new(Map.get(component, :light_ids, []))

    groups
    |> Enum.filter(fn group ->
      group_light_ids = Builder.group_room_light_ids(group, room_light_ids)

      group_light_ids != [] and
        Enum.all?(group_light_ids, &MapSet.member?(component_light_ids, &1))
    end)
    |> Enum.sort_by(fn group ->
      {-Enum.count(component_group_light_ids(component, group, room_light_ids)),
       group |> display_name() |> String.downcase(), group.id}
    end)
  end

  defp component_group_light_ids(component, group, room_light_ids) do
    component_light_ids = MapSet.new(Map.get(component, :light_ids, []))

    group
    |> Builder.group_room_light_ids(room_light_ids)
    |> Enum.filter(&MapSet.member?(component_light_ids, &1))
  end

  defp group_default_power(component, group, room_light_ids) do
    policies =
      component
      |> component_group_light_ids(group, room_light_ids)
      |> Enum.map(&light_default_power(component, &1))
      |> Enum.uniq()

    case policies do
      [policy] -> policy
      _ -> :mixed
    end
  end

  defp display_name(entity), do: Util.display_name(entity)

  defp selected_state_id(%{light_state_id: light_state_id}), do: parse_id(light_state_id)
  defp selected_state_id(_component), do: nil

  defp state_option_label(%{type: :circadian, name: name}), do: "#{name} (circadian)"

  defp state_option_label(%{type: :manual, name: name, config: config}) do
    suffix =
      case LightState.manual_mode(config) do
        :color -> "manual color"
        _ -> "manual temp"
      end

    "#{name} (#{suffix})"
  end

  defp state_option_label(%{name: name}), do: name

  defp normalize_component_light_defaults(socket) do
    components =
      Enum.map(socket.assigns.components, fn component ->
        light_ids = Map.get(component, :light_ids, [])

        defaults =
          component
          |> Map.get(:light_defaults, %{})
          |> normalize_light_defaults_map()
          |> keep_defaults_for_light_ids(light_ids)
          |> ensure_defaults_for_light_ids(light_ids)

        Map.put(component, :light_defaults, defaults)
      end)

    assign(socket, components: components)
  end

  defp normalize_component_light_states(socket) do
    valid_ids =
      socket.assigns.light_states |> Enum.map(& &1.id) |> Enum.map(&to_string/1) |> MapSet.new()

    components =
      Enum.map(socket.assigns.components, fn component ->
        Map.put(
          component,
          :light_state_id,
          normalize_light_state_id(Map.get(component, :light_state_id), valid_ids)
        )
      end)

    assign(socket, components: components)
  end

  defp normalize_light_state_id(nil, _valid_ids), do: nil
  defp normalize_light_state_id("", _valid_ids), do: nil

  defp normalize_light_state_id(state_id, valid_ids) do
    state_id = to_string(state_id)
    if MapSet.member?(valid_ids, state_id), do: state_id, else: nil
  end

  defp parse_id(value), do: Util.parse_id(value)

  defp normalize_light_defaults_map(defaults) when is_map(defaults) do
    Enum.reduce(defaults, %{}, fn {key, value}, acc ->
      case parse_id(key) do
        nil -> acc
        light_id -> Map.put(acc, light_id, normalize_default_power_value(value))
      end
    end)
  end

  defp normalize_light_defaults_map(_defaults), do: %{}

  defp keep_defaults_for_light_ids(defaults, light_ids) do
    allowed_ids = MapSet.new(light_ids)

    defaults
    |> Enum.filter(fn {light_id, _} -> MapSet.member?(allowed_ids, light_id) end)
    |> Map.new()
  end

  defp ensure_defaults_for_light_ids(defaults, light_ids) do
    Enum.reduce(light_ids, defaults, fn light_id, acc -> Map.put_new(acc, light_id, :force_on) end)
  end

  defp normalize_default_power_value(value) when value in [:force_on, "force_on"], do: :force_on

  defp normalize_default_power_value(value) when value in [:force_off, "force_off"],
    do: :force_off

  defp normalize_default_power_value(value) when value in [:follow_occupancy, "follow_occupancy"],
    do: :follow_occupancy

  defp normalize_default_power_value(value) when value in [true, "true", 1, "1", :on, "on"],
    do: :force_on

  defp normalize_default_power_value(value) when value in [false, "false", 0, "0", :off, "off"],
    do: :force_off

  defp normalize_default_power_value(_value), do: :force_on

  defp next_power_policy(:force_on), do: :force_off
  defp next_power_policy(:force_off), do: :follow_occupancy
  defp next_power_policy(:follow_occupancy), do: :force_on
  defp next_power_policy(:mixed), do: :force_on
  defp next_power_policy(_policy), do: :force_on

  defp power_policy_label(:force_on), do: "Default On"
  defp power_policy_label(:force_off), do: "Default Off"
  defp power_policy_label(:follow_occupancy), do: "Follow Occupancy"
  defp power_policy_label(:mixed), do: "..."
end
