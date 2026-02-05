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
           edit_name: Hueworks.Util.display_name(room)
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
           scene_name: Hueworks.Util.display_name(scene),
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

  def handle_event("activate_scene", %{"id" => id}, socket) do
    _ = Scenes.activate_scene(String.to_integer(id))
    {:noreply, socket}
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
