defmodule HueworksWeb.SceneEditorLive do
  use Phoenix.LiveView

  alias Hueworks.ActiveScenes
  alias Hueworks.Groups
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias Hueworks.Scenes.Builder
  alias HueworksWeb.SceneBuilderComponent.Component

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
       activation_transition_mode: "default",
       activation_transition_value: "",
       activation_transition_unit: "seconds",
       scene_components: [Component.new()],
       scene_builder: nil,
       scene_room_lights: [],
       scene_room_groups: [],
       scene_presence_inputs: [],
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

  def handle_event("update_scene", params, socket) do
    {:noreply,
     assign(socket,
       scene_name: Map.get(params, "name", socket.assigns.scene_name),
       activation_transition_mode:
         Map.get(params, "activation_transition_mode", socket.assigns.activation_transition_mode),
       activation_transition_value:
         Map.get(
           params,
           "activation_transition_value",
           socket.assigns.activation_transition_value
         ),
       activation_transition_unit:
         Map.get(params, "activation_transition_unit", socket.assigns.activation_transition_unit)
     )}
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
    case Scenes.toggle_activation(socket.assigns.scene_id, :scene_editor) do
      {:ok, :deactivated, _scene} ->
        {:noreply,
         socket
         |> assign(active_scene_id: nil)
         |> put_flash(:info, "Scene deactivated.")}

      {:ok, :activated, scene, _diff, _updated} ->
        {:noreply,
         socket
         |> assign(active_scene_id: scene.id)
         |> put_flash(:info, "Scene activated.")}

      {:error, :not_found} ->
        {:noreply, push_navigate(socket, to: "/rooms")}

      {:error, _reason} ->
        {:noreply, put_scene_error(socket, "Unable to activate scene.")}
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
        assign_new_scene(socket, room, "", [Component.new()])

      {:ok, room, scene} ->
        assign_new_scene(
          socket,
          room,
          cloned_scene_name(scene),
          load_scene_components(scene),
          scene.activation_transition_ms
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
          {room_lights, room_groups, presence_inputs} = scene_room_data(room_id)
          light_states = Scenes.list_editable_light_states()
          components = load_scene_components(scene)
          builder = Builder.build(room_lights, room_groups, components)
          active_scene_id = active_scene_id_for_room(room_id)
          {transition_value, transition_unit} = transition_fields(scene.activation_transition_ms)

          assign(socket,
            room_id: room_id,
            room_name: Hueworks.Util.display_name(room),
            scene_mode: :edit,
            scene_id: scene.id,
            scene_name: Hueworks.Util.display_name(scene),
            activation_transition_mode: transition_mode(scene.activation_transition_ms),
            activation_transition_value: transition_value,
            activation_transition_unit: transition_unit,
            scene_components: components,
            scene_builder: builder,
            scene_room_lights: room_lights,
            scene_room_groups: room_groups,
            scene_presence_inputs: presence_inputs,
            scene_light_states: light_states,
            active_scene_id: active_scene_id,
            scene_save_error: nil
          )
        end
    end
  end

  defp save_new_scene(socket, name) do
    with {:ok, transition_attrs} <- transition_attrs(socket) do
      attrs = %{name: name, room_id: socket.assigns.room_id} |> Map.merge(transition_attrs)

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
    else
      {:error, message} ->
        {:noreply, put_scene_error(socket, message)}
    end
  end

  defp save_existing_scene(socket, name) do
    case Scenes.get_scene(socket.assigns.scene_id) do
      nil ->
        {:noreply, push_navigate(socket, to: "/rooms")}

      scene ->
        with {:ok, transition_attrs} <- transition_attrs(socket) do
          attrs =
            if name == "" do
              %{display_name: nil}
            else
              %{display_name: name}
            end
            |> Map.merge(transition_attrs)

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
        else
          {:error, message} ->
            {:noreply, put_scene_error(socket, message)}
        end
    end
  end

  defp assign_new_scene(socket, room, scene_name, components, activation_transition_ms \\ nil) do
    room_id = room.id
    {room_lights, room_groups, presence_inputs} = scene_room_data(room_id)
    light_states = Scenes.list_editable_light_states()
    builder = Builder.build(room_lights, room_groups, components)
    {transition_value, transition_unit} = transition_fields(activation_transition_ms)

    assign(socket,
      room_id: room_id,
      room_name: Hueworks.Util.display_name(room),
      scene_mode: :new,
      scene_id: nil,
      scene_name: scene_name,
      activation_transition_mode: transition_mode(activation_transition_ms),
      activation_transition_value: transition_value,
      activation_transition_unit: transition_unit,
      scene_components: components,
      scene_builder: builder,
      scene_room_lights: room_lights,
      scene_room_groups: room_groups,
      scene_presence_inputs: presence_inputs,
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

    components = Enum.map(scene.scene_components, &Component.from_saved/1)

    case components do
      [] -> [Component.new()]
      _ -> components
    end
  end

  defp scene_room_data(room_id) do
    case Rooms.get_room(room_id) do
      nil ->
        {[], [], []}

      room ->
        room = Repo.preload(room, [:lights, :groups, :presence_inputs])
        groups = room.groups
        group_ids = Enum.map(groups, & &1.id)
        group_light_map = Groups.light_ids_by_group(group_ids)

        groups_with_lights =
          Enum.map(groups, fn group ->
            light_ids = Map.get(group_light_map, group.id, [])
            Map.put(group, :light_ids, light_ids)
          end)

        {room.lights, groups_with_lights, room.presence_inputs}
    end
  end

  defp active_scene_id_for_room(room_id) when is_integer(room_id) do
    case ActiveScenes.get_for_room(room_id) do
      %{scene_id: scene_id} -> scene_id
      _ -> nil
    end
  end

  defp active_scene_id_for_room(_room_id), do: nil

  defp transition_attrs(%{assigns: %{activation_transition_mode: "default"}}),
    do: {:ok, %{activation_transition_ms: nil}}

  defp transition_attrs(%{assigns: %{activation_transition_mode: "custom"} = assigns}) do
    with {value, ""} when value > 0 <- Integer.parse(assigns.activation_transition_value),
         multiplier when is_integer(multiplier) <-
           transition_unit_multiplier(assigns.activation_transition_unit) do
      {:ok, %{activation_transition_ms: value * multiplier}}
    else
      _ -> {:error, "Custom activation transition must be a positive duration."}
    end
  end

  defp transition_attrs(_socket), do: {:error, "Choose a valid activation transition."}

  defp transition_mode(duration_ms) when is_integer(duration_ms) and duration_ms > 0, do: "custom"
  defp transition_mode(_duration_ms), do: "default"

  defp transition_fields(duration_ms) when is_integer(duration_ms) and duration_ms > 0 do
    cond do
      rem(duration_ms, 60_000) == 0 -> {Integer.to_string(div(duration_ms, 60_000)), "minutes"}
      rem(duration_ms, 1_000) == 0 -> {Integer.to_string(div(duration_ms, 1_000)), "seconds"}
      true -> {Integer.to_string(duration_ms), "milliseconds"}
    end
  end

  defp transition_fields(_duration_ms), do: {"", "seconds"}

  defp transition_unit_multiplier("milliseconds"), do: 1
  defp transition_unit_multiplier("seconds"), do: 1_000
  defp transition_unit_multiplier("minutes"), do: 60_000
  defp transition_unit_multiplier(_unit), do: nil

  defp parse_id(value), do: Hueworks.Util.parse_id(value)
end
