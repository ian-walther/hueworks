defmodule HueworksWeb.RoomsLive do
  use Phoenix.LiveView

  alias Hueworks.Rooms
  alias Hueworks.Scenes

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       rooms: Rooms.list_rooms_with_children(),
       modal_open: false,
       edit_mode: :new,
       edit_room_id: nil,
       edit_name: ""
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
    case Hueworks.Util.parse_id(id) do
      nil ->
        {:noreply, socket}

      room_id ->
        {:noreply, push_navigate(socket, to: "/rooms/#{room_id}/scenes/new")}
    end
  end

  def handle_event("open_scene_edit", %{"id" => id}, socket) do
    case Scenes.get_scene(Hueworks.Util.parse_id(id)) do
      nil ->
        {:noreply, socket}

      scene ->
        {:noreply, push_navigate(socket, to: "/rooms/#{scene.room_id}/scenes/#{scene.id}/edit")}
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
      edit_name: ""
    )
  end
end
