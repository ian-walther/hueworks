defmodule HueworksWeb.RoomsLive do
  use Phoenix.LiveView

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias Hueworks.Scenes.Builder
  alias Hueworks.Repo
  alias Hueworks.Schemas.GroupLight

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       rooms: Rooms.list_rooms_with_children(),
       modal_open: false,
       edit_mode: :new,
       edit_room_id: nil,
       edit_name: "",
       scene_modal_open: false,
       scene_mode: :new,
       scene_room_id: nil,
       scene_id: nil,
       scene_name: "",
       scene_components: [%{id: 1, name: "Component 1", light_ids: [], group_ids: []}],
       scene_builder: nil,
       scene_room_lights: [],
       scene_room_groups: [],
       scene_light_states: [],
       scene_save_error: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="hw-shell">
      <div class="hw-topbar">
        <div>
          <h1 class="hw-title">Rooms</h1>
          <p class="hw-subtitle">Manage room names and assignments.</p>
        </div>
        <div class="hw-actions">
          <button class="hw-button" phx-click="open_new">
            <span class="hw-button-icon">+</span>
            Add
          </button>
        </div>
      </div>

      <div class="hw-list">
        <%= for room <- @rooms do %>
          <div class="hw-card" id={"room-#{room.id}"}>
            <div class="hw-card-title">
              <div class="hw-title-row">
                <h3><%= room.display_name || room.name %></h3>
                <button
                  type="button"
                  class="hw-edit-button"
                  phx-click="open_edit"
                  phx-value-id={room.id}
                  aria-label="Edit room name"
                >
                  <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                    <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3l-10 10L6 17l.5-3.5 10-10z"></path>
                  </svg>
                </button>
                <button
                  type="button"
                  class="hw-edit-button hw-delete-button"
                  phx-click="delete_room"
                  phx-value-id={room.id}
                  aria-label="Delete room"
                >
                  <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                    <path d="M9 3h6l1 2h4v2H4V5h4l1-2zm1 6h2v8h-2V9zm4 0h2v8h-2V9z"></path>
                  </svg>
                </button>
                <button
                  type="button"
                  class="hw-edit-button hw-add-scene-button"
                  phx-click="open_scene_new"
                  phx-value-id={room.id}
                  aria-label="Add scene"
                >
                  <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                    <path d="M11 5h2v14h-2z"></path>
                    <path d="M5 11h14v2H5z"></path>
                  </svg>
                </button>
              </div>
            </div>
            <div class="hw-room-scenes">
              <div class="hw-room-scenes-header">
                <p class="hw-room-label">Scenes</p>
                <button
                  type="button"
                  class="hw-edit-button hw-add-scene-button"
                  phx-click="open_scene_new"
                  phx-value-id={room.id}
                  aria-label="Add scene"
                >
                  <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                    <path d="M11 5h2v14h-2z"></path>
                    <path d="M5 11h14v2H5z"></path>
                  </svg>
                </button>
              </div>
              <div class="hw-room-list">
                <%= for scene <- room.scenes do %>
                  <div class="hw-room-item hw-room-item-row">
                    <span><%= scene.display_name || scene.name %></span>
                    <span class="hw-room-item-actions">
                      <button
                        type="button"
                        class="hw-edit-button"
                        phx-click="open_scene_edit"
                        phx-value-id={scene.id}
                        aria-label="Edit scene"
                      >
                        <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                          <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3l-10 10L6 17l.5-3.5 10-10z"></path>
                        </svg>
                      </button>
                      <button
                        type="button"
                        class="hw-edit-button hw-delete-button"
                        phx-click="delete_scene"
                        phx-value-id={scene.id}
                        aria-label="Delete scene"
                      >
                        <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                          <path d="M9 3h6l1 2h4v2H4V5h4l1-2zm1 6h2v8h-2V9zm4 0h2v8h-2V9z"></path>
                        </svg>
                      </button>
                    </span>
                  </div>
                <% end %>
                <%= if Enum.empty?(room.scenes) do %>
                  <span class="hw-room-item hw-room-empty">None</span>
                <% end %>
              </div>
            </div>
            <div class="hw-room-grid">
              <div>
                <details class="hw-room-section">
                  <summary class="hw-room-label">Groups</summary>
                  <div class="hw-room-list">
                    <%= for group <- room.groups do %>
                      <span class="hw-room-item"><%= group.display_name || group.name %></span>
                    <% end %>
                    <%= if Enum.empty?(room.groups) do %>
                      <span class="hw-room-item hw-room-empty">None</span>
                    <% end %>
                  </div>
                </details>
              </div>
              <div>
                <details class="hw-room-section">
                  <summary class="hw-room-label">Lights</summary>
                  <div class="hw-room-list">
                    <%= for light <- room.lights do %>
                      <span class="hw-room-item"><%= light.display_name || light.name %></span>
                    <% end %>
                    <%= if Enum.empty?(room.lights) do %>
                      <span class="hw-room-item hw-room-empty">None</span>
                    <% end %>
                  </div>
                </details>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <%= if @modal_open do %>
      <div class="hw-modal-backdrop">
        <div class="hw-modal" phx-click-away="close_modal">
          <div class="hw-modal-header">
            <h3><%= if @edit_mode == :edit, do: "Edit Room", else: "Add Room" %></h3>
            <button type="button" class="hw-modal-close" phx-click="close_modal" aria-label="Close">
              ×
            </button>
          </div>
          <form phx-submit="save_room" phx-change="update_room">
            <label class="hw-modal-label" for="room_name">Name</label>
            <input
              id="room_name"
              name="name"
              type="text"
              value={@edit_name}
              class="hw-modal-input"
              autocomplete="off"
            />
            <div class="hw-modal-actions">
              <button type="button" class="hw-button hw-button-off" phx-click="close_modal">
                Cancel
              </button>
              <button type="submit" class="hw-button hw-button-on">Save</button>
            </div>
          </form>
        </div>
      </div>
    <% end %>

    <%= if @scene_modal_open do %>
      <div class="hw-modal-backdrop">
        <div class="hw-modal" phx-click-away="close_scene_modal">
          <div class="hw-modal-header">
            <h3><%= if @scene_mode == :edit, do: "Edit Scene", else: "Add Scene" %></h3>
            <button type="button" class="hw-modal-close" phx-click="close_scene_modal" aria-label="Close">
              ×
            </button>
          </div>
          <div>
            <%= if @scene_save_error do %>
              <p class="hw-error"><%= @scene_save_error %></p>
            <% end %>
            <form phx-change="update_scene">
              <label class="hw-modal-label" for="scene_name">Name</label>
              <input
                id="scene_name"
                name="name"
                type="text"
                value={@scene_name}
                class="hw-modal-input"
                autocomplete="off"
              />
            </form>
            <.live_component
              module={HueworksWeb.SceneBuilderComponent}
              id="scene-builder"
              room_lights={@scene_room_lights}
              groups={@scene_room_groups}
              components={@scene_components}
              light_states={@scene_light_states}
              scene_id={@scene_id}
            />
            <div class="hw-modal-actions">
              <button type="button" class="hw-button hw-button-off" phx-click="close_scene_modal">
                Cancel
              </button>
              <button type="button" class="hw-button hw-button-on" phx-click="save_scene">Save</button>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  def handle_event("open_new", _params, socket) do
    {:noreply,
     assign(socket,
       modal_open: true,
       edit_mode: :new,
       edit_room_id: nil,
       edit_name: ""
     )}
  end

  def handle_event("open_edit", %{"id" => id}, socket) do
    case Rooms.get_room(String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      room ->
        {:noreply,
         assign(socket,
           modal_open: true,
           edit_mode: :edit,
           edit_room_id: room.id,
           edit_name: room.display_name || room.name
         )}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal_open: false)}
  end

  def handle_event("open_scene_new", %{"id" => id}, socket) do
    {room_lights, room_groups} = scene_room_data(String.to_integer(id))
    light_states = Scenes.list_manual_light_states()

    components = [
      %{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: "off"}
    ]

    builder = Builder.build(room_lights, room_groups, components)

    {:noreply,
     assign(socket,
       scene_modal_open: true,
       scene_mode: :new,
       scene_room_id: String.to_integer(id),
       scene_id: nil,
       scene_name: "",
       scene_components: components,
       scene_builder: builder,
       scene_room_lights: room_lights,
       scene_room_groups: room_groups,
       scene_light_states: light_states,
       scene_save_error: nil
     )}
  end

  def handle_event("open_scene_edit", %{"id" => id}, socket) do
    case Scenes.get_scene(String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      scene ->
        {room_lights, room_groups} = scene_room_data(scene.room_id)
        light_states = Scenes.list_manual_light_states()
        components = load_scene_components(scene)
        builder = Builder.build(room_lights, room_groups, components)

        {:noreply,
         assign(socket,
           scene_modal_open: true,
           scene_mode: :edit,
           scene_room_id: scene.room_id,
           scene_id: scene.id,
           scene_name: scene.display_name || scene.name,
           scene_components: components,
           scene_builder: builder,
           scene_room_lights: room_lights,
           scene_room_groups: room_groups,
           scene_light_states: light_states,
           scene_save_error: nil
         )}
    end
  end

  def handle_event("close_scene_modal", _params, socket) do
    {:noreply, assign(socket, scene_modal_open: false, scene_save_error: nil)}
  end

  def handle_event("update_scene", %{"name" => name}, socket) do
    {:noreply, assign(socket, scene_name: name)}
  end

  def handle_event("save_scene", params, socket) do
    name = Map.get(params, "name", socket.assigns.scene_name)

    if is_nil(socket.assigns.scene_builder) do
      {:noreply, assign(socket, scene_save_error: "Assign all lights once before saving.")}
    else
      if socket.assigns.scene_builder && socket.assigns.scene_builder.valid? == false do
        {:noreply, assign(socket, scene_save_error: "Assign all lights once before saving.")}
      else
        case socket.assigns.scene_mode do
          :new ->
            attrs = %{name: name, room_id: socket.assigns.scene_room_id}

            case Scenes.create_scene(attrs) do
              {:ok, scene} ->
                _ = Scenes.replace_scene_components(scene, socket.assigns.scene_components)
                {:noreply, refresh_rooms(socket)}

              {:error, _changeset} ->
                {:noreply, assign(socket, scene_save_error: "Scene name is required.")}
            end

          :edit ->
            case Scenes.get_scene(socket.assigns.scene_id) do
              nil ->
                {:noreply, socket}

              scene ->
                attrs =
                  if name == "" do
                    %{display_name: nil}
                  else
                    %{display_name: name}
                  end

                case Scenes.update_scene(scene, attrs) do
                  {:ok, updated} ->
                    _ = Scenes.replace_scene_components(updated, socket.assigns.scene_components)
                    {:noreply, refresh_rooms(socket)}

                  {:error, _changeset} ->
                    {:noreply, assign(socket, scene_save_error: "Scene name is required.")}
                end
            end
        end
      end
    end
  end

  def handle_event("delete_scene", %{"id" => id}, socket) do
    case Scenes.get_scene(String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      scene ->
        _ = Scenes.delete_scene(scene)
        {:noreply, refresh_rooms(socket)}
    end
  end

  def handle_event("update_room", %{"name" => name}, socket) do
    {:noreply, assign(socket, edit_name: name)}
  end

  def handle_event("save_room", %{"name" => name}, socket) do
    case socket.assigns.edit_mode do
      :new ->
        case Rooms.create_room(%{name: name}) do
          {:ok, _room} ->
            {:noreply, refresh_rooms(socket)}

          {:error, _changeset} ->
            {:noreply, socket}
        end

      :edit ->
        case Rooms.get_room(socket.assigns.edit_room_id) do
          nil ->
            {:noreply, socket}

          room ->
            attrs =
              if name == "" do
                %{display_name: nil}
              else
                %{display_name: name}
              end

            case Rooms.update_room(room, attrs) do
              {:ok, _room} -> {:noreply, refresh_rooms(socket)}
              {:error, _changeset} -> {:noreply, socket}
            end
        end
    end
  end

  def handle_event("delete_room", %{"id" => id}, socket) do
    case Rooms.get_room(String.to_integer(id)) do
      nil ->
        {:noreply, socket}

      room ->
        _ = Rooms.delete_room(room)
        {:noreply, refresh_rooms(socket)}
    end
  end

  defp refresh_rooms(socket) do
    assign(socket,
      rooms: Rooms.list_rooms_with_children(),
      modal_open: false,
      edit_mode: :new,
      edit_room_id: nil,
      edit_name: "",
      scene_modal_open: false,
      scene_mode: :new,
      scene_room_id: nil,
      scene_id: nil,
      scene_name: "",
      scene_components: [
        %{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: "off"}
      ],
      scene_builder: nil,
      scene_room_lights: [],
      scene_room_groups: [],
      scene_light_states: [],
      scene_save_error: nil
    )
  end

  def handle_info({:scene_builder_updated, components, builder}, socket) do
    socket =
      socket
      |> assign(scene_components: components, scene_builder: builder)
      |> maybe_clear_scene_save_error()

    {:noreply, socket}
  end

  def handle_info({:scene_light_states_updated, light_states}, socket) do
    {:noreply, assign(socket, scene_light_states: light_states)}
  end

  defp maybe_clear_scene_save_error(socket) do
    if socket.assigns.scene_builder && socket.assigns.scene_builder.valid? do
      assign(socket, scene_save_error: nil)
    else
      socket
    end
  end

  defp load_scene_components(scene) do
    scene =
      scene
      |> Repo.preload(scene_components: [:lights, :light_state])

    components =
      Enum.map(scene.scene_components, fn component ->
        %{
          id: component.id,
          name: component.name || "Component",
          light_ids: Enum.map(component.lights, & &1.id),
          group_ids: [],
          light_state_id: to_string(component.light_state_id),
          light_state_config: component.light_state && component.light_state.config
        }
      end)

    case components do
      [] -> [%{id: 1, name: "Component 1", light_ids: [], group_ids: [], light_state_id: "off"}]
      _ -> components
    end
  end

  defp scene_room_data(room_id) do
    case Rooms.get_room(room_id) do
      nil ->
        {[], []}

      room ->
        room = Repo.preload(room, [:lights, :groups])
        groups = room.groups
        group_ids = Enum.map(groups, & &1.id)

        group_light_map =
          Repo.all(
            from(gl in GroupLight,
              where: gl.group_id in ^group_ids,
              select: {gl.group_id, gl.light_id}
            )
          )
          |> Enum.group_by(
            fn {group_id, _light_id} -> group_id end,
            fn {_group_id, light_id} -> light_id end
          )

        groups_with_lights =
          Enum.map(groups, fn group ->
            light_ids = Map.get(group_light_map, group.id, [])
            Map.put(group, :light_ids, light_ids)
          end)

        {room.lights, groups_with_lights}
    end
  end
end
