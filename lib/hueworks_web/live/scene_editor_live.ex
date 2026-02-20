defmodule HueworksWeb.SceneEditorLive do
  use Phoenix.LiveView

  import Ecto.Query, only: [from: 2]

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
    light_state_id: "off"
  }

  def mount(_params, _session, socket) do
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
       scene_save_error: nil
     )}
  end

  def handle_params(params, _uri, socket) do
    room_id = parse_id(params["room_id"])

    cond do
      is_nil(room_id) ->
        {:noreply, push_navigate(socket, to: "/rooms")}

      socket.assigns.live_action == :new ->
        {:noreply, load_new_scene(socket, room_id)}

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
        {:noreply, assign(socket, scene_save_error: "Assign all lights once before saving.")}

      socket.assigns.scene_builder.valid? == false ->
        {:noreply, assign(socket, scene_save_error: "Assign all lights once before saving.")}

      socket.assigns.scene_mode == :new ->
        save_new_scene(socket, name)

      socket.assigns.scene_mode == :edit ->
        save_existing_scene(socket, name)

      true ->
        {:noreply, assign(socket, scene_save_error: "Unable to save scene.")}
    end
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

  defp load_new_scene(socket, room_id) do
    case Rooms.get_room(room_id) do
      nil ->
        push_navigate(socket, to: "/rooms")

      room ->
        {room_lights, room_groups} = scene_room_data(room_id)
        light_states = Scenes.list_editable_light_states()
        builder = Builder.build(room_lights, room_groups, [@blank_component])

        assign(socket,
          room_id: room_id,
          room_name: Hueworks.Util.display_name(room),
          scene_mode: :new,
          scene_id: nil,
          scene_name: "",
          scene_components: [@blank_component],
          scene_builder: builder,
          scene_room_lights: room_lights,
          scene_room_groups: room_groups,
          scene_light_states: light_states,
          scene_save_error: nil
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
            scene_save_error: nil
          )
        end
    end
  end

  defp save_new_scene(socket, name) do
    attrs = %{name: name, room_id: socket.assigns.room_id}

    case Scenes.create_scene(attrs) do
      {:ok, scene} ->
        _ = Scenes.replace_scene_components(scene, socket.assigns.scene_components)
        {:noreply, push_navigate(socket, to: "/rooms")}

      {:error, _changeset} ->
        {:noreply, assign(socket, scene_save_error: "Scene name is required.")}
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
            _ = Scenes.replace_scene_components(updated, socket.assigns.scene_components)
            {:noreply, push_navigate(socket, to: "/rooms")}

          {:error, _changeset} ->
            {:noreply, assign(socket, scene_save_error: "Scene name is required.")}
        end
    end
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

  defp parse_id(value), do: Hueworks.Util.parse_id(value)
end
