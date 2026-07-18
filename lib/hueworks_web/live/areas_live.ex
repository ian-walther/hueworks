defmodule HueworksWeb.AreasLive do
  use Phoenix.LiveView

  alias Hueworks.ActiveScenes
  alias Hueworks.PresenceInputs
  alias Hueworks.Areas
  alias Hueworks.Scenes
  alias Hueworks.Util

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())
    end

    areas = Areas.list_areas_with_children()
    scene_assigns = active_scene_assigns(areas)

    {:ok,
     assign(socket,
       areas: areas,
       active_scene_by_area: scene_assigns.active_scene_by_area,
       modal_open: false,
       edit_mode: :new,
       edit_area_id: nil,
       edit_name: ""
     )}
  end

  def handle_info({:active_scene_updated, area_id, scene_id}, socket) do
    {:noreply,
     assign(socket,
       active_scene_by_area:
         put_active_scene(socket.assigns.active_scene_by_area, area_id, scene_id)
     )}
  end

  def handle_event("open_new", _params, socket) do
    {:noreply,
     assign(socket,
       modal_open: true,
       edit_mode: :new,
       edit_area_id: nil,
       edit_name: ""
     )}
  end

  def handle_event("open_edit", %{"id" => id}, socket) do
    with area_id when is_integer(area_id) <- Util.parse_id(id),
         %{} = area <- Areas.get_area(area_id) do
      {:noreply,
       assign(socket,
         modal_open: true,
         edit_mode: :edit,
         edit_area_id: area.id,
         edit_name: Hueworks.Util.display_name(area)
       )}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal_open: false)}
  end

  def handle_event("open_scene_new", %{"id" => id}, socket) do
    case Util.parse_id(id) do
      nil ->
        {:noreply, socket}

      area_id ->
        {:noreply, push_navigate(socket, to: "/areas/#{area_id}/scenes/new")}
    end
  end

  def handle_event("open_scene_edit", %{"id" => id}, socket) do
    with scene_id when is_integer(scene_id) <- Util.parse_id(id),
         %{} = scene <- Scenes.get_scene(scene_id) do
      {:noreply, push_navigate(socket, to: "/areas/#{scene.area_id}/scenes/#{scene.id}/edit")}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("open_scene_clone", %{"id" => id}, socket) do
    with scene_id when is_integer(scene_id) <- Util.parse_id(id),
         %{} = scene <- Scenes.get_scene(scene_id) do
      {:noreply,
       push_navigate(socket,
         to: "/areas/#{scene.area_id}/scenes/new?clone_scene_id=#{scene.id}"
       )}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_scene", %{"id" => id}, socket) do
    with scene_id when is_integer(scene_id) <- Util.parse_id(id),
         %{} = scene <- Scenes.get_scene(scene_id) do
      _ = Scenes.delete_scene(scene)
      {:noreply, refresh_areas(socket)}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("activate_scene", %{"id" => id}, socket) do
    with scene_id when is_integer(scene_id) <- Util.parse_id(id),
         {:ok, _action, _scene} <-
           normalize_toggle_result(Scenes.toggle_activation(scene_id, :areas_live)) do
      {:noreply, assign(socket, active_scene_assigns())}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("update_area", %{"name" => name}, socket) do
    {:noreply, assign(socket, edit_name: name)}
  end

  def handle_event("save_area", %{"name" => name}, socket) do
    case socket.assigns.edit_mode do
      :new ->
        case Areas.create_area(%{name: name}) do
          {:ok, _area} ->
            {:noreply, refresh_areas(socket)}

          {:error, _changeset} ->
            {:noreply, socket}
        end

      :edit ->
        case Areas.get_area(socket.assigns.edit_area_id) do
          nil ->
            {:noreply, socket}

          area ->
            attrs =
              if name == "" do
                %{display_name: nil}
              else
                %{display_name: name}
              end

            case Areas.update_area(area, attrs) do
              {:ok, _area} -> {:noreply, refresh_areas(socket)}
              {:error, _changeset} -> {:noreply, socket}
            end
        end
    end
  end

  def handle_event("create_presence_input", %{"area_id" => area_id, "name" => name}, socket) do
    with area_id when is_integer(area_id) <- Util.parse_id(area_id),
         trimmed when trimmed != "" <- String.trim(name) do
      _ = PresenceInputs.create_input(area_id, %{name: trimmed, occupied: false, metadata: %{}})
      {:noreply, refresh_areas(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update_presence_input", %{"input_id" => input_id, "name" => name}, socket) do
    with input_id when is_integer(input_id) <- Util.parse_id(input_id),
         trimmed when trimmed != "" <- String.trim(name),
         %{} = input <- PresenceInputs.get_input(input_id) do
      _ = PresenceInputs.update_input(input, %{name: trimmed})
      {:noreply, refresh_areas(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_presence_input", %{"id" => input_id}, socket) do
    with input_id when is_integer(input_id) <- Util.parse_id(input_id),
         %{} = input <- PresenceInputs.get_input(input_id) do
      _ = PresenceInputs.delete_input(input)
      {:noreply, refresh_areas(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_area", %{"id" => id}, socket) do
    with area_id when is_integer(area_id) <- Util.parse_id(id),
         %{} = area <- Areas.get_area(area_id) do
      _ = Areas.delete_area(area)
      {:noreply, refresh_areas(socket)}
    else
      _ ->
        {:noreply, socket}
    end
  end

  defp refresh_areas(socket) do
    areas = Areas.list_areas_with_children()
    scene_assigns = active_scene_assigns(areas)

    assign(socket,
      areas: areas,
      active_scene_by_area: scene_assigns.active_scene_by_area,
      modal_open: false,
      edit_mode: :new,
      edit_area_id: nil,
      edit_name: ""
    )
  end

  defp active_scene_assigns do
    active_scene_assigns(Areas.list_areas_with_children())
  end

  defp active_scene_assigns(areas) do
    active_scenes = ActiveScenes.list_active_scenes()

    %{
      active_scene_by_area:
        Map.new(active_scenes, fn active -> {active.area_id, active.scene_id} end),
      areas: areas
    }
  end

  defp put_active_scene(active_scene_by_area, area_id, scene_id) do
    active_scene_by_area = active_scene_by_area || %{}

    case scene_id do
      scene_id when is_integer(scene_id) -> Map.put(active_scene_by_area, area_id, scene_id)
      _ -> Map.delete(active_scene_by_area, area_id)
    end
  end

  defp count_label(items, singular) when is_list(items) do
    count = length(items)
    label = if count == 1, do: singular, else: singular <> "s"
    "#{count} #{label}"
  end

  defp presence_summary([]), do: "No inputs configured"

  defp presence_summary(inputs) when is_list(inputs) do
    occupied_count = Enum.count(inputs, & &1.occupied)
    "#{count_label(inputs, "input")}, #{occupied_count} occupied"
  end

  defp sort_by_display_name(items) when is_list(items) do
    Enum.sort_by(items, &Hueworks.Util.display_name/1)
  end

  defp normalize_toggle_result({:ok, :activated, scene, _diff, _updated}),
    do: {:ok, :activated, scene}

  defp normalize_toggle_result(result), do: result
end
