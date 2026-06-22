defmodule HueworksWeb.SceneEditorLive do
  use Phoenix.LiveView

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ActiveScenes
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias Hueworks.Scenes.Builder
  alias Hueworks.Schemas.GroupLight

  @blank_component %{
    id: 1,
    name: "Component 1",
    light_ids: [],
    group_ids: [],
    light_state_id: nil,
    embedded_manual_config: nil,
    light_defaults: %{}
  }

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())
    end

    {:ok,
     assign(socket,
       room_id: nil,
       room_name: "",
       scene_mode: :new,
       scene_id: nil,
       scene_name: "",
       scene_components: [@blank_component],
       scene_builder: nil,
       scene_room_lights: [],
       scene_room_groups: [],
       scene_light_states: [],
       active_scene_id: nil,
       scene_save_error: nil
     )}
  end

  def handle_params(params, _uri, socket) do
    room_id = parse_id(params["room_id"])
    clone_scene_id = parse_id(params["clone_scene_id"])

    cond do
      is_nil(room_id) ->
        {:noreply, push_navigate(socket, to: "/rooms")}

      socket.assigns.live_action == :new ->
        {:noreply, load_new_scene(socket, room_id, clone_scene_id)}

      socket.assigns.live_action == :edit ->
        scene_id = parse_id(params["id"])
        {:noreply, load_existing_scene(socket, room_id, scene_id)}

      true ->
        {:noreply, push_navigate(socket, to: "/rooms")}
    end
  end

  def handle_event("update_scene", %{"name" => name}, socket) do
    {:noreply, assign(socket, scene_name: name)}
  end

  def handle_event("save_scene", params, socket) do
    name = Map.get(params, "name", socket.assigns.scene_name)

    cond do
      is_nil(socket.assigns.scene_builder) ->
        {:noreply, put_scene_error(socket, "Assign all lights once before saving.")}

      socket.assigns.scene_builder.valid? == false ->
        {:noreply, put_scene_error(socket, "Assign all lights once before saving.")}

      socket.assigns.scene_mode == :new ->
        save_new_scene(socket, name)

      socket.assigns.scene_mode == :edit ->
        save_existing_scene(socket, name)

      true ->
        {:noreply, put_scene_error(socket, "Unable to save scene.")}
    end
  end

  def handle_event("toggle_scene_activation", _params, %{assigns: %{scene_id: nil}} = socket) do
    {:noreply, put_scene_error(socket, "Save the scene before activating it.")}
  end

  def handle_event("toggle_scene_activation", _params, socket) do
    case Scenes.get_scene(socket.assigns.scene_id) do
      nil ->
        {:noreply, push_navigate(socket, to: "/rooms")}

      scene ->
        if socket.assigns.active_scene_id == scene.id do
          :ok = ActiveScenes.clear_for_room(scene.room_id)

          {:noreply,
           socket
           |> assign(active_scene_id: nil)
           |> put_flash(:info, "Scene deactivated.")}
        else
          with {:ok, _active} <- ActiveScenes.set_active(scene),
               {:ok, _diff, _updated} <- Scenes.activate_scene(scene.id) do
            {:noreply,
             socket
             |> assign(active_scene_id: scene.id)
             |> put_flash(:info, "Scene activated.")}
          else
            _ ->
              {:noreply, put_scene_error(socket, "Unable to activate scene.")}
          end
        end
    end
  end

  def handle_info({:scene_builder_updated, components, builder}, socket) do
    socket =
      socket
      |> assign(scene_components: components, scene_builder: builder)
      |> maybe_clear_scene_save_error()

    {:noreply, socket}
  end

  def handle_info({:active_scene_updated, room_id, scene_id}, socket) do
    {:noreply,
     if socket.assigns.room_id == room_id do
       assign(socket, active_scene_id: scene_id)
     else
       socket
     end}
  end

  defp load_new_scene(socket, room_id, clone_scene_id) do
    case clone_source(room_id, clone_scene_id) do
      {:error, :invalid_clone} ->
        push_navigate(socket, to: "/rooms")

      {:ok, room, nil} ->
        assign_new_scene(socket, room, "", [@blank_component])

      {:ok, room, scene} ->
        assign_new_scene(
          socket,
          room,
          cloned_scene_name(scene),
          load_scene_components(scene)
        )
    end
  end

  defp load_existing_scene(socket, room_id, scene_id) do
    case {Rooms.get_room(room_id), scene_id && Scenes.get_scene(scene_id)} do
      {nil, _} ->
        push_navigate(socket, to: "/rooms")

      {_, nil} ->
        push_navigate(socket, to: "/rooms")

      {room, scene} ->
        if scene.room_id != room_id do
          push_navigate(socket, to: "/rooms")
        else
          {room_lights, room_groups} = scene_room_data(room_id)
          light_states = Scenes.list_editable_light_states()
          components = load_scene_components(scene)
          builder = Builder.build(room_lights, room_groups, components)
          active_scene_id = active_scene_id_for_room(room_id)

          assign(socket,
            room_id: room_id,
            room_name: Hueworks.Util.display_name(room),
            scene_mode: :edit,
            scene_id: scene.id,
            scene_name: Hueworks.Util.display_name(scene),
            scene_components: components,
            scene_builder: builder,
            scene_room_lights: room_lights,
            scene_room_groups: room_groups,
            scene_light_states: light_states,
            active_scene_id: active_scene_id,
            scene_save_error: nil
          )
        end
    end
  end

  defp save_new_scene(socket, name) do
    attrs = %{name: name, room_id: socket.assigns.room_id}

    case Scenes.create_scene(attrs) do
      {:ok, scene} ->
        case Scenes.replace_scene_components(scene, socket.assigns.scene_components) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Scene saved.")
             |> push_patch(to: "/rooms/#{scene.room_id}/scenes/#{scene.id}/edit")}

          {:error, :invalid_light_state} ->
            _ = Scenes.delete_scene(scene)

            {:noreply,
             put_scene_error(
               socket,
               "Each component must use a saved light state or custom manual state before saving."
             )}

          {:error, :invalid_color_targets} ->
            _ = Scenes.delete_scene(scene)

            {:noreply,
             put_scene_error(
               socket,
               "Manual color states can only target lights that support color."
             )}

          {:error, _} ->
            _ = Scenes.delete_scene(scene)
            {:noreply, put_scene_error(socket, "Unable to save scene components.")}
        end

      {:error, _changeset} ->
        {:noreply, put_scene_error(socket, "Scene name is required.")}
    end
  end

  defp save_existing_scene(socket, name) do
    case Scenes.get_scene(socket.assigns.scene_id) do
      nil ->
        {:noreply, push_navigate(socket, to: "/rooms")}

      scene ->
        attrs =
          if name == "" do
            %{display_name: nil}
          else
            %{display_name: name}
          end

        case Scenes.update_scene(scene, attrs) do
          {:ok, updated} ->
            case Scenes.replace_scene_components(updated, socket.assigns.scene_components) do
              {:ok, _} ->
                _ = Scenes.refresh_active_scene(updated.id)

                {:noreply,
                 socket
                 |> assign(active_scene_id: active_scene_id_for_room(updated.room_id))
                 |> put_flash(:info, "Scene saved.")}

              {:error, :invalid_light_state} ->
                {:noreply,
                 put_scene_error(
                   socket,
                   "Each component must use a saved light state or custom manual state before saving."
                 )}

              {:error, :invalid_color_targets} ->
                {:noreply,
                 put_scene_error(
                   socket,
                   "Manual color states can only target lights that support color."
                 )}

              {:error, _} ->
                {:noreply, put_scene_error(socket, "Unable to save scene components.")}
            end

          {:error, _changeset} ->
            {:noreply, put_scene_error(socket, "Scene name is required.")}
        end
    end
  end

  defp assign_new_scene(socket, room, scene_name, components) do
    room_id = room.id
    {room_lights, room_groups} = scene_room_data(room_id)
    light_states = Scenes.list_editable_light_states()
    builder = Builder.build(room_lights, room_groups, components)

    assign(socket,
      room_id: room_id,
      room_name: Hueworks.Util.display_name(room),
      scene_mode: :new,
      scene_id: nil,
      scene_name: scene_name,
      scene_components: components,
      scene_builder: builder,
      scene_room_lights: room_lights,
      scene_room_groups: room_groups,
      scene_light_states: light_states,
      active_scene_id: active_scene_id_for_room(room_id),
      scene_save_error: nil
    )
  end

  defp clone_source(room_id, nil) do
    case Rooms.get_room(room_id) do
      nil -> {:error, :invalid_clone}
      room -> {:ok, room, nil}
    end
  end

  defp clone_source(room_id, clone_scene_id) do
    case {Rooms.get_room(room_id), Scenes.get_scene(clone_scene_id)} do
      {nil, _} ->
        {:error, :invalid_clone}

      {_, nil} ->
        {:error, :invalid_clone}

      {_room, scene} when scene.room_id != room_id ->
        {:error, :invalid_clone}

      {room, scene} ->
        {:ok, room, scene}
    end
  end

  defp cloned_scene_name(scene) do
    "#{Hueworks.Util.display_name(scene)} Copy"
  end

  defp maybe_clear_scene_save_error(socket) do
    if socket.assigns.scene_builder && socket.assigns.scene_builder.valid? do
      socket
      |> assign(scene_save_error: nil)
      |> clear_flash(:error)
    else
      socket
    end
  end

  defp put_scene_error(socket, message) do
    socket
    |> assign(scene_save_error: message)
    |> put_flash(:error, message)
  end

  defp load_scene_components(scene) do
    scene =
      scene
      |> Repo.preload(scene_components: [:lights, :light_state, :scene_component_lights])

    components =
      Enum.map(scene.scene_components, fn component ->
        light_defaults =
          component.scene_component_lights
          |> Enum.reduce(%{}, fn join, acc ->
            Map.put(acc, join.light_id, join.default_power)
          end)

        %{
          id: component.id,
          name: component.name || "Component",
          light_ids: Enum.map(component.lights, & &1.id),
          group_ids: [],
          light_state_id: if(component.light_state_id, do: to_string(component.light_state_id)),
          embedded_manual_config: component.embedded_manual_config,
          light_defaults: light_defaults
        }
      end)

    case components do
      [] -> [@blank_component]
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

  defp active_scene_id_for_room(room_id) when is_integer(room_id) do
    case ActiveScenes.get_for_room(room_id) do
      %{scene_id: scene_id} -> scene_id
      _ -> nil
    end
  end

  defp active_scene_id_for_room(_room_id), do: nil

  defp parse_id(value), do: Hueworks.Util.parse_id(value)
end
