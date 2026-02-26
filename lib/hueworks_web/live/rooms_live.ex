defmodule HueworksWeb.RoomsLive do
  use Phoenix.LiveView

  alias Hueworks.ActiveScenes
  alias Hueworks.Rooms
  alias Hueworks.Scenes

  def mount(_params, _session, socket) do
    scene_assigns = active_scene_assigns()

    {:ok,
     assign(socket,
       rooms: Rooms.list_rooms_with_children(),
       active_scene_by_room: scene_assigns.active_scene_by_room,
       occupancy_by_room: scene_assigns.occupancy_by_room,
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
    with scene_id when is_integer(scene_id) <- Hueworks.Util.parse_id(id),
         %{} = scene <- Scenes.get_scene(scene_id) do
      case ActiveScenes.get_for_room(scene.room_id) do
        %{scene_id: ^scene_id} ->
          _ = ActiveScenes.clear_for_room(scene.room_id)

        _ ->
          _ = Scenes.activate_scene(scene_id)
      end

      {:noreply, assign(socket, active_scene_assigns())}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_occupancy", %{"room_id" => room_id}, socket) do
    with room_id when is_integer(room_id) <- Hueworks.Util.parse_id(room_id),
         scene_id when is_integer(scene_id) <- active_scene_id_for_room(socket, room_id),
         %{} = scene <- Scenes.get_scene(scene_id) do
      active = ActiveScenes.get_for_room(room_id)
      current_occupied = current_occupied_for_room(socket, room_id, active)
      next_occupied = not current_occupied
      trace = occupancy_trace(room_id, scene_id, current_occupied, next_occupied)

      case active do
        %{} = active_scene ->
          _ = ActiveScenes.set_occupied(room_id, next_occupied)

          _ =
            Scenes.apply_scene(scene,
              brightness_override: active_scene.brightness_override,
              occupied: next_occupied,
              diff_mode: :desired,
              occupancy_only: true,
              trace: trace
            )

          _ = ActiveScenes.mark_applied(active_scene)

        nil ->
          # If an external update cleared active_scenes but the UI still shows an active scene,
          # recreate the active row so this toggle remains usable.
          _ = ActiveScenes.set_active(scene)
          _ = ActiveScenes.set_occupied(room_id, next_occupied)

          _ =
            Scenes.apply_scene(scene,
              brightness_override: false,
              occupied: next_occupied,
              diff_mode: :desired,
              occupancy_only: true,
              trace: trace
            )
      end

      {:noreply, assign(socket, active_scene_assigns())}
    else
      _ ->
        {:noreply, assign(socket, active_scene_assigns())}
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
    scene_assigns = active_scene_assigns()

    assign(socket,
      rooms: Rooms.list_rooms_with_children(),
      active_scene_by_room: scene_assigns.active_scene_by_room,
      occupancy_by_room: scene_assigns.occupancy_by_room,
      modal_open: false,
      edit_mode: :new,
      edit_room_id: nil,
      edit_name: ""
    )
  end

  defp active_scene_assigns do
    active_scenes = ActiveScenes.list_active_scenes()

    %{
      active_scene_by_room:
        Map.new(active_scenes, fn active -> {active.room_id, active.scene_id} end),
      occupancy_by_room:
        Map.new(active_scenes, fn active -> {active.room_id, Map.get(active, :occupied, true)} end)
    }
  end

  defp active_scene_id_for_room(socket, room_id) do
    case ActiveScenes.get_for_room(room_id) do
      %{} = active -> active.scene_id
      nil -> Map.get(socket.assigns.active_scene_by_room || %{}, room_id)
    end
  end

  defp current_occupied_for_room(socket, room_id, nil) do
    Map.get(socket.assigns.occupancy_by_room || %{}, room_id, true)
  end

  defp current_occupied_for_room(_socket, _room_id, %{} = active) do
    Map.get(active, :occupied, true)
  end

  defp occupancy_trace(room_id, scene_id, from_occupied, to_occupied) do
    %{
      trace_id: "occ-#{room_id}-#{System.unique_integer([:positive])}",
      source: "rooms_live.toggle_occupancy",
      room_id: room_id,
      scene_id: scene_id,
      from_occupied: from_occupied,
      to_occupied: to_occupied,
      started_at_ms: System.monotonic_time(:millisecond)
    }
  end
end
