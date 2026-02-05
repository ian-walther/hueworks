defmodule HueworksWeb.SceneBuilderComponent do
  use Phoenix.LiveComponent

  alias Hueworks.Scenes.Builder
  alias Hueworks.Util

  def mount(socket) do
    {:ok,
     assign(socket,
       components: [
         %{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: "off"}
       ],
       room_lights: [],
       groups: [],
       light_states: [],
       scene_id: nil,
       builder: nil,
       selections: %{},
       light_state_error: nil,
       light_state_names: %{},
       light_state_edits: %{},
       light_state_dirty: %{}
     )}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:light_state_error, fn -> nil end)
      |> assign_new(:light_state_names, fn -> %{} end)
      |> assign_new(:light_state_edits, fn -> %{} end)
      |> assign_new(:light_state_dirty, fn -> %{} end)
      |> normalize_component_light_states()
      |> hydrate_light_state_edits_for_components()
      |> hydrate_light_state_names_for_components()

    {:ok, refresh_builder(socket)}
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
                <option value="new" selected={component.light_state_id == "new"}>New</option>
                <option value="off" selected={component.light_state_id == "off"}>Off</option>
                <%= for state <- @light_states do %>
                  <option value={state.id} selected={to_string(state.id) == to_string(component.light_state_id)}>
                    <%= state.name %>
                  </option>
                <% end %>
              </select>
            </form>
            <%= if component.light_state_id not in ["off"] do %>
              <div class="hw-row">
                <button
                  type="button"
                  class="hw-button"
                  phx-click="edit_light_state"
                  phx-target={@myself}
                  phx-value-component_id={component.id}
                  disabled={component.light_state_id in ["new"]}
                >
                  Edit
                </button>
                <button
                  type="button"
                  class="hw-button"
                  phx-click="duplicate_light_state"
                  phx-target={@myself}
                  phx-value-component_id={component.id}
                  disabled={component.light_state_id in ["new"]}
                >
                  Duplicate
                </button>
                <button
                  type="button"
                  class="hw-button hw-button-off"
                  phx-click="delete_light_state"
                  phx-target={@myself}
                  phx-value-component_id={component.id}
                  disabled={component.light_state_id in ["new"]}
                >
                  Delete
                </button>
                <span class="hw-muted">Edits affect all scenes using this state.</span>
              </div>
            <% end %>
            <%= if component.light_state_id != "off" do %>
              <div class="hw-row">
                <form phx-change="update_light_state_form" phx-target={@myself} data-component-id={component.id}>
                  <input type="hidden" name="component_id" value={component.id} />
                  <div class="hw-row">
                    <label class="hw-modal-label">Brightness</label>
                    <span class="hw-slider-value">
                      <%= slider_display(@light_state_edits, @light_states, component, "brightness", "%") %>
                    </span>
                  </div>
                  <input
                    type="range"
                    name="brightness"
                    class="hw-modal-input"
                    min="1"
                    max="100"
                    value={edit_value(@light_state_edits, @light_states, component, "brightness")}
                  />
                  <div class="hw-row">
                    <label class="hw-modal-label">Temperature</label>
                    <span class="hw-slider-value">
                      <%= slider_display(@light_state_edits, @light_states, component, "temperature", "K") %>
                    </span>
                  </div>
                  <input
                    type="range"
                    name="temperature"
                    class="hw-modal-input"
                    min="2000"
                    max="6500"
                    value={edit_value(@light_state_edits, @light_states, component, "temperature")}
                  />
                </form>
              </div>

              <div class="hw-row">
                <label class="hw-modal-label">Light state name</label>
                <form phx-change="select_light_state_name" phx-target={@myself} data-component-id={component.id}>
                  <input type="hidden" name="component_id" value={component.id} />
                  <input
                    type="text"
                    name="name"
                    class="hw-modal-input"
                    autocomplete="off"
                    value={Map.get(@light_state_names, component.id, "")}
                  />
                </form>
                <button
                  type="button"
                  class="hw-button"
                  phx-click="save_light_state_name"
                  phx-target={@myself}
                  phx-value-component_id={component.id}
                >
                  Save state
                </button>
                <%= if Map.get(@light_state_dirty, component.id, false) do %>
                  <span class="hw-muted">(unsaved changes)</span>
                <% end %>
                <%= if @light_state_error do %>
                  <p class="hw-error"><%= @light_state_error %></p>
                <% end %>
              </div>
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

          <div class="hw-room-list">
            <%= for light_id <- component.light_ids do %>
              <span class="hw-room-item hw-room-item-row">
                <span><%= light_name(@room_lights, light_id) %></span>
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
        [
          %{
            id: next_id,
            name: "Component #{next_id}",
            light_ids: [],
            group_ids: [],
            light_state_id: "off"
          }
        ]

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
    component_id = parse_id(id)
    edits = hydrate_light_state_edits(socket, component_id, state_id)
    names = hydrate_light_state_name(socket, component_id, state_id)

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == component_id do
          %{component | light_state_id: state_id}
        else
          component
        end
      end)

    socket =
      socket
      |> assign(components: components, light_state_edits: edits, light_state_names: names)
      |> refresh_builder()

    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("select_light_state_name", %{"component_id" => id, "name" => name}, socket) do
    component_id = parse_id(id)

    light_state_names =
      socket.assigns.light_state_names
      |> Map.put(component_id, name)

    {:noreply, assign(socket, light_state_names: light_state_names)}
  end

  def handle_event("save_light_state_name", %{"component_id" => id} = params, socket) do
    component_id = parse_id(id)

    name =
      Map.get(params, "name") ||
        Map.get(socket.assigns.light_state_names, component_id)

    component = Enum.find(socket.assigns.components, &(&1.id == component_id))

    if component && component.light_state_id not in ["off", "new"] do
      state_id = selected_state_id(component)
      edits = Map.get(socket.assigns.light_state_edits, component_id, %{})

      case Hueworks.Scenes.update_manual_light_state(state_id, %{name: name, config: edits}) do
        {:ok, updated} ->
          light_states =
            Enum.map(socket.assigns.light_states, fn state ->
              if state.id == updated.id, do: updated, else: state
            end)

          light_state_names =
            Map.put(socket.assigns.light_state_names, component_id, updated.name)

          socket =
            socket
            |> assign(
              light_states: light_states,
              light_state_error: nil,
              light_state_names: light_state_names,
              light_state_dirty: Map.put(socket.assigns.light_state_dirty, component_id, false)
            )
            |> refresh_builder()

          notify_light_states(socket)
          {:noreply, socket}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, light_state_error: Util.format_changeset_error(changeset))}

        {:error, _reason} ->
          {:noreply, assign(socket, light_state_error: "Unable to update light state name.")}
      end
    else
      edits = Map.get(socket.assigns.light_state_edits, component_id, %{})

      case Hueworks.Scenes.create_manual_light_state(name, edits) do
        {:ok, state} ->
          edits = hydrate_light_state_edits(socket, component_id, to_string(state.id))
          names = hydrate_light_state_name(socket, component_id, to_string(state.id))

          components =
            Enum.map(socket.assigns.components, fn component ->
              if component.id == component_id do
                %{component | light_state_id: to_string(state.id)}
              else
                component
              end
            end)

          socket =
            socket
            |> assign(
              light_states: socket.assigns.light_states ++ [state],
              components: components,
              light_state_error: nil,
              light_state_names: names,
              light_state_edits: edits,
              light_state_dirty: Map.put(socket.assigns.light_state_dirty, component_id, false)
            )
            |> refresh_builder()

          notify_parent(socket)
          notify_light_states(socket)
          {:noreply, socket}

        {:error, changeset} ->
          {:noreply, assign(socket, light_state_error: Util.format_changeset_error(changeset))}
      end
    end
  end

  def handle_event("update_light_state_form", %{"component_id" => id} = params, socket) do
    component_id = parse_id(id)
    current = Map.get(socket.assigns.light_state_edits, component_id, %{})

    edits =
      current
      |> Map.put("brightness", Map.get(params, "brightness"))
      |> Map.put("temperature", Map.get(params, "temperature"))

    {:noreply,
     assign(socket,
       light_state_edits: Map.put(socket.assigns.light_state_edits, component_id, edits),
       light_state_dirty: Map.put(socket.assigns.light_state_dirty, component_id, true)
     )}
  end

  def handle_event("edit_light_state", %{"component_id" => id}, socket) do
    component_id = parse_id(id)
    component = Enum.find(socket.assigns.components, &(&1.id == component_id))
    state_id = selected_state_id(component)
    edits = Map.get(socket.assigns.light_state_edits, component_id, %{})

    case Hueworks.Scenes.update_manual_light_state(state_id, %{config: edits}) do
      {:ok, updated} ->
        light_states =
          Enum.map(socket.assigns.light_states, fn state ->
            if state.id == updated.id, do: updated, else: state
          end)

        {:noreply, assign(socket, light_states: light_states, light_state_error: nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, light_state_error: Util.format_changeset_error(changeset))}

      {:error, _reason} ->
        {:noreply, assign(socket, light_state_error: "Unable to update light state.")}
    end
  end

  def handle_event("duplicate_light_state", %{"component_id" => id}, socket) do
    component_id = parse_id(id)
    component = Enum.find(socket.assigns.components, &(&1.id == component_id))
    state_id = selected_state_id(component)

    case Hueworks.Scenes.duplicate_manual_light_state(state_id) do
      {:ok, state} ->
        components =
          Enum.map(socket.assigns.components, fn component ->
            if component.id == component_id do
              %{component | light_state_id: to_string(state.id)}
            else
              component
            end
          end)

        edits = hydrate_light_state_edits(socket, component_id, to_string(state.id))
        names = hydrate_light_state_name(socket, component_id, to_string(state.id))

        socket =
          socket
          |> assign(
            components: components,
            light_states: socket.assigns.light_states ++ [state],
            light_state_edits: edits,
            light_state_error: nil,
            light_state_names: names
          )
          |> refresh_builder()

        notify_parent(socket)
        notify_light_states(socket)
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, assign(socket, light_state_error: "Unable to duplicate light state.")}
    end
  end

  def handle_event("delete_light_state", %{"component_id" => id}, socket) do
    component_id = parse_id(id)
    component = Enum.find(socket.assigns.components, &(&1.id == component_id))
    state_id = selected_state_id(component)

    case Hueworks.Scenes.delete_manual_light_state(state_id, scene_id: socket.assigns.scene_id) do
      {:ok, _} ->
        light_states = Enum.reject(socket.assigns.light_states, &(&1.id == state_id))

        components =
          Enum.map(socket.assigns.components, fn component ->
            if component.id == component_id do
              %{component | light_state_id: "off"}
            else
              component
            end
          end)

        socket =
          socket
          |> assign(
            components: components,
            light_states: light_states,
            light_state_error: nil,
            light_state_edits: Map.delete(socket.assigns.light_state_edits, component_id),
            light_state_names: Map.put(socket.assigns.light_state_names, component_id, ""),
            light_state_dirty: Map.delete(socket.assigns.light_state_dirty, component_id)
          )
          |> refresh_builder()

        notify_parent(socket)
        notify_light_states(socket)
        {:noreply, socket}

      {:error, :in_use} ->
        {:noreply, assign(socket, light_state_error: "Light state is in use by other scenes.")}

      {:error, _reason} ->
        {:noreply, assign(socket, light_state_error: "Unable to delete light state.")}
    end
  end

  def handle_event("add_light", %{"component_id" => id}, socket) do
    light_id = Map.get(socket.assigns[:selections] || %{}, {:light, parse_id(id)})

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == parse_id(id) and is_integer(light_id) do
          %{component | light_ids: Enum.uniq(component.light_ids ++ [light_id])}
        else
          component
        end
      end)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("add_group", %{"component_id" => id}, socket) do
    group_id = Map.get(socket.assigns[:selections] || %{}, {:group, parse_id(id)})
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))

    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == parse_id(id) and group do
          light_ids = Enum.uniq(component.light_ids ++ group.light_ids)
          group_ids = Enum.uniq(component.group_ids ++ [group_id])
          %{component | light_ids: light_ids, group_ids: group_ids}
        else
          component
        end
      end)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("remove_light", %{"component_id" => id, "light_id" => light_id}, socket) do
    components =
      Enum.map(socket.assigns.components, fn component ->
        if component.id == parse_id(id) do
          %{component | light_ids: List.delete(component.light_ids, parse_id(light_id))}
        else
          component
        end
      end)

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  def handle_event("remove_component", %{"component_id" => id}, socket) do
    components =
      socket.assigns.components
      |> Enum.reject(&(&1.id == parse_id(id)))

    components =
      case components do
        [] -> [%{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: "off"}]
        _ -> components
      end

    socket = refresh_builder(assign(socket, components: components))
    notify_parent(socket)
    {:noreply, socket}
  end

  defp refresh_builder(socket) do
    room_lights = List.wrap(socket.assigns.room_lights)
    groups = List.wrap(socket.assigns.groups)
    components = List.wrap(socket.assigns.components)

    builder = Builder.build(room_lights, groups, components)
    assign(socket, builder: builder)
  end

  defp notify_parent(socket) do
    send(self(), {:scene_builder_updated, socket.assigns.components, socket.assigns.builder})
  end

  defp notify_light_states(socket) do
    send(self(), {:scene_light_states_updated, socket.assigns.light_states})
  end

  defp light_name(lights, id) do
    case Enum.find(lights, &(&1.id == id)) do
      nil -> "Light #{id}"
      light -> display_name(light)
    end
  end

  defp display_name(%{display_name: display_name, name: name}) do
    display_name || name
  end

  defp display_name(%{name: name}), do: name
  defp display_name(_), do: "Unknown"

  defp selected_state_id(nil), do: nil
  defp selected_state_id(%{light_state_id: "off"}), do: nil

  defp selected_state_id(%{light_state_id: light_state_id}) do
    parse_id(light_state_id)
  end

  defp parse_id(nil), do: nil
  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_id(_value), do: nil

  defp hydrate_light_state_edits(socket, component_id, state_id) do
    edits = socket.assigns.light_state_edits
    selected_id = parse_id(state_id)

    updated =
      case Enum.find(socket.assigns.light_states, &(&1.id == selected_id)) do
        nil ->
          Map.get(edits, component_id, %{})

        state ->
          config = state.config || %{}

          %{
            "brightness" => Map.get(config, "brightness") || Map.get(config, :brightness) || "",
            "temperature" => Map.get(config, "temperature") || Map.get(config, :temperature) || ""
          }
      end

    Map.put(edits, component_id, updated)
  end

  defp edit_value(edits, light_states, component, key) do
    component_id = Map.get(component, :id)

    case edits |> Map.get(component_id, %{}) |> Map.get(key) do
      nil ->
        config =
          Map.get(component, :light_state_config) ||
            light_state_config(light_states, selected_state_id(component))

        config_value(config || %{}, key)

      value ->
        value
    end
  end

  defp slider_display(edits, light_states, component, key, suffix) do
    value = edit_value(edits, light_states, component, key)

    case Util.to_number(value) do
      nil -> "--"
      number -> "#{round(number)}#{suffix}"
    end
  end

  defp light_state_config(_light_states, nil), do: %{}

  defp light_state_config(light_states, state_id) do
    case Enum.find(light_states, &(&1.id == state_id)) do
      nil -> %{}
      state -> state.config || %{}
    end
  end

  defp config_value(config, "brightness") do
    Map.get(config, "brightness") || Map.get(config, :brightness) || ""
  end

  defp config_value(config, "temperature") do
    Map.get(config, "temperature") || Map.get(config, :temperature) || ""
  end

  defp config_value(config, key) do
    Map.get(config, key) || ""
  end

  defp hydrate_light_state_edits_for_components(socket) do
    edits = socket.assigns.light_state_edits
    components = List.wrap(socket.assigns.components)

    updated =
      Enum.reduce(components, edits, fn component, acc ->
        component_id = Map.get(component, :id)

        cond do
          component_id in [nil, ""] ->
            acc

          Map.has_key?(acc, component_id) ->
            acc

          Map.get(component, :light_state_id) in [nil, "off", :off] ->
            acc

          true ->
            hydrate_light_state_edits(
              %{socket | assigns: %{socket.assigns | light_state_edits: acc}},
              component_id,
              Map.get(component, :light_state_id)
            )
        end
      end)

    assign(socket, light_state_edits: updated)
  end

  defp normalize_component_light_states(socket) do
    light_state_ids =
      socket.assigns.light_states
      |> Enum.map(& &1.id)
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    {components, edits} =
      socket.assigns.components
      |> Enum.reduce({[], socket.assigns.light_state_edits}, fn component, {acc, edits} ->
        state_id = Map.get(component, :light_state_id)
        normalized = normalize_light_state_id(state_id, light_state_ids)

        updated_component =
          if normalized == state_id do
            component
          else
            %{component | light_state_id: normalized}
          end

        updated_edits =
          if normalized == "off" do
            Map.delete(edits, Map.get(component, :id))
          else
            edits
          end

        {[updated_component | acc], updated_edits}
      end)

    assign(socket, components: Enum.reverse(components), light_state_edits: edits)
  end

  defp hydrate_light_state_name(socket, component_id, state_id) do
    name =
      if to_string(state_id) == "new" do
        ""
      else
        state = Enum.find(socket.assigns.light_states, &(&1.id == parse_id(state_id)))
        if state, do: state.name, else: ""
      end

    Map.put(socket.assigns.light_state_names, component_id, name)
  end

  defp hydrate_light_state_names_for_components(socket) do
    components = List.wrap(socket.assigns.components)

    updated =
      Enum.reduce(components, socket.assigns.light_state_names, fn component, acc ->
        component_id = Map.get(component, :id)
        state_id = Map.get(component, :light_state_id)

        cond do
          component_id in [nil, ""] ->
            acc

          Map.has_key?(acc, component_id) ->
            acc

          true ->
            Map.put(acc, component_id, light_state_name(socket, state_id))
        end
      end)

    assign(socket, light_state_names: updated)
  end

  defp light_state_name(socket, state_id) do
    state = Enum.find(socket.assigns.light_states, &(&1.id == parse_id(state_id)))
    if state, do: state.name, else: ""
  end

  defp normalize_light_state_id(nil, _ids), do: "off"
  defp normalize_light_state_id("off", _ids), do: "off"
  defp normalize_light_state_id("new", _ids), do: "new"
  defp normalize_light_state_id(:off, _ids), do: "off"

  defp normalize_light_state_id(state_id, ids) do
    state_id = to_string(state_id)
    if MapSet.member?(ids, state_id), do: state_id, else: "off"
  end
end
