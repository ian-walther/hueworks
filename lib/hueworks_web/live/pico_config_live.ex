defmodule HueworksWeb.PicoConfigLive do
  use Phoenix.LiveView

  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hueworks.PubSub, Picos.topic())
    end

    {:ok,
     assign(socket,
       bridge: nil,
       pico_devices: [],
       selected_pico: nil,
       detect_pico_mode: false,
       all_rooms: [],
       room_groups: [],
       room_lights: [],
       room_scenes: [],
       selectable_room_groups: [],
       selectable_room_lights: [],
       control_groups: [],
       clone_source_pico_id: nil,
       selected_control_group_id: nil,
       editing_control_group_name: false,
       control_group_name: "",
       control_group_name_draft: "",
       control_group_group_ids: [],
       control_group_light_ids: [],
       selected_control_group_group_id: nil,
       selected_control_group_light_id: nil,
       binding_target_kind: "control_groups",
       binding_target_id: nil,
       binding_target_group_ids: [],
       binding_action: "toggle",
       learning_binding: nil,
       editing_display_name: false,
       save_status: nil,
       save_error: nil
     )}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
    bridge_id = Util.parse_id(id)
    pico_id = Util.parse_id(params["pico_id"])

    case Repo.get(Bridge, bridge_id) do
      %Bridge{type: :caseta} = bridge ->
        case {socket.assigns.live_action, pico_id} do
          {:show, nil} ->
            {:noreply, push_navigate(socket, to: pico_index_path(bridge.id))}

          _ ->
            {:noreply, load_page(socket, bridge, pico_id)}
        end

      _ ->
        {:noreply, push_navigate(socket, to: "/config")}
    end
  end

  def handle_event("sync_picos", _params, socket) do
    case Picos.sync_bridge_picos(socket.assigns.bridge) do
      {:ok, devices} ->
        selected_id =
          case socket.assigns.live_action do
            :show -> socket.assigns.selected_pico && socket.assigns.selected_pico.id
            _ -> nil
          end

        socket
        |> assign(save_status: "Picos synced.", save_error: nil)
        |> reload_from_devices(devices, selected_id)
        |> reply_with_save_notice()

      {:error, reason} ->
        socket
        |> assign(save_status: nil, save_error: inspect(reason))
        |> reply_with_save_notice()
    end
  end

  def handle_event("select_pico", %{"id" => id}, socket) do
    pico_id = Util.parse_id(id)
    {:noreply, push_patch(socket, to: pico_show_path(socket.assigns.bridge.id, pico_id))}
  end

  def handle_event("start_detect_pico", _params, socket) do
    socket
    |> assign(
      detect_pico_mode: true,
      save_status: "Detect mode active. Press a Pico button to open that Pico.",
      save_error: nil
    )
    |> reply_with_save_notice()
  end

  def handle_event("cancel_detect_pico", _params, socket) do
    socket
    |> assign(
      detect_pico_mode: false,
      save_status: "Detect mode cancelled.",
      save_error: nil
    )
    |> reply_with_save_notice()
  end

  def handle_event("save_room_override", %{"room_id" => room_id}, socket) do
    case socket.assigns.selected_pico do
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      device ->
        case maybe_set_pico_room(device, room_id) do
          {:ok, updated} ->
            devices = Picos.list_devices_for_bridge(socket.assigns.bridge.id)

            socket
            |> assign(save_status: "Pico room updated.", save_error: nil)
            |> reload_from_devices(devices, updated.id)
            |> reply_with_save_notice()

          {:error, reason} ->
            message =
              case reason do
                :config_present ->
                  "Clear this Pico's control groups and button bindings before changing rooms."

                _ ->
                  inspect(reason)
              end

            socket
            |> assign(save_status: nil, save_error: message)
            |> reply_with_save_notice()
        end
    end
  end

  def handle_event("clear_pico_config", _params, socket) do
    case socket.assigns.selected_pico do
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      device ->
        case Picos.clear_device_config(device) do
          {:ok, updated} ->
            devices = Picos.list_devices_for_bridge(socket.assigns.bridge.id)

            socket
            |> assign(save_status: "Pico config cleared.", save_error: nil)
            |> reload_from_devices(devices, updated.id)
            |> reply_with_save_notice()

          {:error, reason} ->
            socket
            |> assign(save_status: nil, save_error: inspect(reason))
            |> reply_with_save_notice()
        end
    end
  end

  def handle_event("save_pico_display_name", %{"display_name" => display_name}, socket) do
    case socket.assigns.selected_pico do
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      device ->
        case Picos.update_display_name(device, %{display_name: display_name}) do
          {:ok, updated} ->
            devices = Picos.list_devices_for_bridge(socket.assigns.bridge.id)

            socket
            |> assign(
              save_status: "Pico name updated.",
              save_error: nil,
              editing_display_name: false
            )
            |> reload_from_devices(devices, updated.id)
            |> reply_with_save_notice()

          {:error, reason} ->
            socket
            |> assign(save_status: nil, save_error: inspect(reason))
            |> reply_with_save_notice()
        end
    end
  end

  def handle_event("edit_pico_display_name", _params, socket) do
    {:noreply, assign(socket, editing_display_name: true)}
  end

  def handle_event("cancel_pico_display_name", _params, socket) do
    {:noreply, assign(socket, editing_display_name: false)}
  end

  def handle_event("select_clone_source", %{"id" => id}, socket) do
    {:noreply, assign(socket, clone_source_pico_id: Util.parse_optional_integer(id))}
  end

  def handle_event("clone_pico_config", _params, socket) do
    with %{} = destination <- socket.assigns.selected_pico,
         source_id when is_integer(source_id) <- socket.assigns.clone_source_pico_id,
         %{} = source <- Enum.find(socket.assigns.pico_devices, &(&1.id == source_id)),
         {:ok, updated} <- Picos.clone_device_config(destination, source) do
      socket
      |> assign(save_status: "Pico config copied.", save_error: nil)
      |> reload_from_devices(Picos.list_devices_for_bridge(socket.assigns.bridge.id), updated.id)
      |> reply_with_save_notice()
    else
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Choose another Pico to copy from.")
        |> reply_with_save_notice()

      {:error, :same_device} ->
        socket
        |> assign(save_status: nil, save_error: "Choose a different Pico to copy from.")
        |> reply_with_save_notice()

      {:error, :missing_source_room} ->
        socket
        |> assign(
          save_status: nil,
          save_error: "The source Pico needs a room before it can be copied."
        )
        |> reply_with_save_notice()

      {:error, reason} ->
        socket
        |> assign(save_status: nil, save_error: inspect(reason))
        |> reply_with_save_notice()
    end
  end

  def handle_event("create_control_group", _params, socket) do
    case socket.assigns.selected_pico do
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      device ->
        group_id = Ecto.UUID.generate()

        case Picos.save_control_group(device, %{
               "id" => group_id,
               "name" => next_control_group_name(socket.assigns.control_groups),
               "group_ids" => [],
               "light_ids" => []
             }) do
          {:ok, updated} ->
            socket
            |> assign(
              save_status: "Control group created.",
              save_error: nil
            )
            |> reload_from_devices(
              Picos.list_devices_for_bridge(socket.assigns.bridge.id),
              updated.id
            )
            |> select_control_group(group_id)
            |> reply_with_save_notice()

          {:error, :missing_room} ->
            socket
            |> assign(save_status: nil, save_error: "Set the Pico room first.")
            |> reply_with_save_notice()

          {:error, reason} ->
            socket
            |> assign(save_status: nil, save_error: inspect(reason))
            |> reply_with_save_notice()
        end
    end
  end

  def handle_event("select_control_group", %{"id" => id}, socket) do
    {:noreply,
     if socket.assigns.selected_control_group_id == to_string(id) do
       deselect_control_group(socket)
     else
       select_control_group(socket, id)
     end}
  end

  def handle_event("start_control_group_name_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing_control_group_name: true,
       control_group_name_draft: socket.assigns.control_group_name
     )}
  end

  def handle_event("update_control_group_name_draft", %{"name" => name}, socket) do
    {:noreply, assign(socket, control_group_name_draft: name)}
  end

  def handle_event("cancel_control_group_name_edit", _params, socket) do
    {:noreply,
     assign(socket,
       editing_control_group_name: false,
       control_group_name_draft: socket.assigns.control_group_name
     )}
  end

  def handle_event("save_control_group_name", %{"name" => name}, socket) do
    socket
    |> assign(control_group_name_draft: name)
    |> persist_selected_control_group_name()
    |> reply_with_save_notice()
  end

  def handle_event("select_control_group_entity", %{"entity" => entity, "id" => id}, socket) do
    key =
      case entity do
        "group" -> :selected_control_group_group_id
        "light" -> :selected_control_group_light_id
      end

    {selection_key, list_key} =
      case entity do
        "group" -> {:selected_control_group_group_id, :control_group_group_ids}
        "light" -> {:selected_control_group_light_id, :control_group_light_ids}
      end

    selected_id = Util.parse_optional_integer(id)

    socket =
      if is_integer(selected_id) do
        socket
        |> assign(list_key, Enum.uniq(socket.assigns[list_key] ++ [selected_id]))
        |> assign(selection_key, nil)
        |> persist_selected_control_group()
      else
        assign(socket, key, nil)
      end

    {:noreply, socket}
  end

  def handle_event("remove_control_group_entity", %{"entity" => entity, "id" => id}, socket) do
    list_key =
      case entity do
        "group" -> :control_group_group_ids
        "light" -> :control_group_light_ids
      end

    entity_id = Util.parse_optional_integer(id)

    {:noreply,
     if is_integer(entity_id) do
       socket
       |> assign(list_key, Enum.reject(socket.assigns[list_key], &(&1 == entity_id)))
       |> persist_selected_control_group()
     else
       socket
     end}
  end

  def handle_event("save_control_group", _params, socket) do
    case {socket.assigns.selected_pico, socket.assigns.selected_control_group_id} do
      {nil, _} ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      {_, nil} ->
        socket
        |> assign(save_status: nil, save_error: "Select or create a control group first.")
        |> reply_with_save_notice()

      {device, group_id} ->
        attrs = %{
          "id" => group_id,
          "name" => socket.assigns.control_group_name,
          "group_ids" => socket.assigns.control_group_group_ids,
          "light_ids" => socket.assigns.control_group_light_ids
        }

        case Picos.save_control_group(device, attrs) do
          {:ok, updated} ->
            socket
            |> assign(save_status: "Control group saved.", save_error: nil)
            |> reload_from_devices(
              Picos.list_devices_for_bridge(socket.assigns.bridge.id),
              updated.id
            )
            |> select_control_group(group_id)
            |> reply_with_save_notice()

          {:error, :invalid_targets} ->
            socket
            |> assign(
              save_status: nil,
              save_error: "Control group targets must stay in the Pico room."
            )
            |> reply_with_save_notice()

          {:error, :invalid_name} ->
            socket
            |> assign(save_status: nil, save_error: "Control groups need a name.")
            |> reply_with_save_notice()

          {:error, reason} ->
            socket
            |> assign(save_status: nil, save_error: inspect(reason))
            |> reply_with_save_notice()
        end
    end
  end

  def handle_event("delete_control_group", %{"id" => id}, socket) do
    group_id = to_string(id)

    case socket.assigns.selected_pico do
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      device ->
        {:ok, updated} = Picos.delete_control_group(device, group_id)

        socket
        |> assign(save_status: "Control group deleted.", save_error: nil)
        |> reload_from_devices(
          Picos.list_devices_for_bridge(socket.assigns.bridge.id),
          updated.id
        )
        |> reply_with_save_notice()
    end
  end

  def handle_event("update_binding_editor", params, socket) do
    action = params["action"] || socket.assigns.binding_action
    binding_target_kind = normalize_binding_target_kind(action)

    {:noreply,
     assign(socket,
       binding_target_kind: binding_target_kind,
       binding_target_id:
         normalize_binding_target_id(
           binding_target_kind,
           params["target_id"] || socket.assigns.binding_target_id
         ),
       binding_target_group_ids:
         normalize_binding_target_group_ids(
           socket.assigns.control_groups,
           params["target_ids"] || socket.assigns.binding_target_group_ids
         ),
       binding_action: normalize_binding_action(action)
     )}
  end

  def handle_event("start_button_learning", _params, socket) do
    learning_binding = current_binding(socket)

    with %{} <- socket.assigns.selected_pico,
         true <-
           valid_learning_binding?(
             learning_binding,
             socket.assigns.control_groups,
             socket.assigns.room_scenes
           ) do
      socket
      |> assign(
        learning_binding: learning_binding,
        save_status: "Press a button on this Pico to assign the selected action.",
        save_error: nil
      )
      |> reply_with_save_notice()
    else
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      false ->
        socket
        |> assign(
          save_status: nil,
          save_error: "Choose an action and a target before starting button learning."
        )
        |> reply_with_save_notice()
    end
  end

  def handle_event("assign_button_manually", %{"id" => id}, socket) do
    button_id = Util.parse_id(id)
    binding = current_binding(socket)

    with %{} = device <- socket.assigns.selected_pico,
         %{} = button <- Enum.find(device.buttons, &(&1.id == button_id)),
         true <-
           valid_learning_binding?(
             binding,
             socket.assigns.control_groups,
             socket.assigns.room_scenes
           ),
         {:ok, _updated} <- Picos.assign_button_binding(device, button.source_id, binding) do
      socket
      |> assign(
        learning_binding: nil,
        save_status: "Assigned action to the selected Pico button.",
        save_error: nil
      )
      |> reload_from_devices(Picos.list_devices_for_bridge(socket.assigns.bridge.id), device.id)
      |> reply_with_save_notice()
    else
      nil ->
        socket
        |> assign(save_status: nil, save_error: "Select a Pico first.")
        |> reply_with_save_notice()

      false ->
        socket
        |> assign(
          save_status: nil,
          save_error: "Choose an action and a target before assigning the button."
        )
        |> reply_with_save_notice()

      {:error, reason} ->
        socket
        |> assign(
          learning_binding: nil,
          save_status: nil,
          save_error: "Failed to assign selected button: #{inspect(reason)}"
        )
        |> reply_with_save_notice()
    end
  end

  def handle_event("cancel_button_learning", _params, socket) do
    socket
    |> assign(
      learning_binding: nil,
      save_status: "Button learning cancelled.",
      save_error: nil
    )
    |> reply_with_save_notice()
  end

  def handle_event("clear_button_binding", %{"id" => id}, socket) do
    button_id = Util.parse_id(id)

    case Enum.find(socket.assigns.selected_pico.buttons, &(&1.id == button_id)) do
      nil ->
        {:noreply, socket}

      button ->
        case Picos.clear_button_binding(button) do
          {:ok, _updated} ->
            socket
            |> assign(save_status: "Button binding cleared.", save_error: nil)
            |> reload_from_devices(
              Picos.list_devices_for_bridge(socket.assigns.bridge.id),
              socket.assigns.selected_pico.id
            )
            |> reply_with_save_notice()

          {:error, reason} ->
            socket
            |> assign(save_status: nil, save_error: inspect(reason))
            |> reply_with_save_notice()
        end
    end
  end

  def handle_info({:pico_button_press, pico_device_id, button_source_id}, socket) do
    if Enum.any?(socket.assigns.pico_devices, &(&1.id == pico_device_id)) do
      cond do
        socket.assigns.live_action == :index and socket.assigns.detect_pico_mode ->
          socket
          |> assign(
            detect_pico_mode: false,
            save_status: "Pico detected. Opening configuration.",
            save_error: nil
          )
          |> push_patch(to: pico_show_path(socket.assigns.bridge.id, pico_device_id))
          |> reply_with_save_notice()

        socket.assigns.selected_pico && socket.assigns.selected_pico.id == pico_device_id &&
            socket.assigns.learning_binding ->
          case Picos.assign_button_binding(
                 socket.assigns.selected_pico,
                 button_source_id,
                 socket.assigns.learning_binding
               ) do
            {:ok, _button} ->
              socket
              |> assign(
                learning_binding: nil,
                save_status: "Assigned action to the pressed Pico button.",
                save_error: nil
              )
              |> reload_from_devices(
                Picos.list_devices_for_bridge(socket.assigns.bridge.id),
                pico_device_id
              )
              |> reply_with_save_notice()

            {:error, reason} ->
              socket
              |> assign(
                learning_binding: nil,
                save_status: nil,
                save_error: "Failed to assign pressed button: #{inspect(reason)}"
              )
              |> reply_with_save_notice()
          end

        socket.assigns.live_action == :show ->
          socket
          |> push_patch(to: pico_show_path(socket.assigns.bridge.id, pico_device_id))
          |> assign(save_status: "Detected Pico button press.", save_error: nil)
          |> reply_with_save_notice()

        true ->
          socket
          |> assign(save_status: "Detected Pico button press.", save_error: nil)
          |> reply_with_save_notice()
      end
    else
      {:noreply, socket}
    end
  end

  defp load_page(socket, bridge, pico_id) do
    devices = Picos.list_devices_for_bridge(bridge.id)

    selected_id =
      case socket.assigns.live_action do
        :show -> normalize_selected_pico_id(devices, pico_id)
        _ -> nil
      end

    rooms = Rooms.list_rooms()

    socket
    |> assign(bridge: bridge, all_rooms: rooms)
    |> reload_from_devices(devices, selected_id)
  end

  defp reload_from_devices(socket, devices, selected_id) do
    selected = Enum.find(devices, &(&1.id == selected_id))

    {groups, lights} =
      case selected && selected.room_id do
        room_id when is_integer(room_id) -> Picos.list_room_targets(room_id)
        _ -> {[], []}
      end

    room_scenes =
      case selected && selected.room_id do
        room_id when is_integer(room_id) -> Scenes.list_scenes_for_room(room_id)
        _ -> []
      end

    control_groups = if selected, do: Picos.control_groups(selected), else: []
    binding_target_kind = normalize_binding_target_kind(socket.assigns[:binding_action])

    selected_control_group_id =
      normalize_selected_control_group_id(
        control_groups,
        socket.assigns[:selected_control_group_id]
      )

    socket =
      assign(socket,
        pico_devices: devices,
        detect_pico_mode:
          if(socket.assigns.live_action == :index,
            do: socket.assigns[:detect_pico_mode] || false,
            else: false
          ),
        selected_pico: selected,
        room_groups: groups,
        room_lights: lights,
        room_scenes: room_scenes,
        selectable_room_groups: selectable_groups(groups),
        selectable_room_lights: selectable_lights(lights),
        control_groups: control_groups,
        clone_source_pico_id:
          normalize_clone_source_id(devices, selected, socket.assigns[:clone_source_pico_id]),
        selected_control_group_id: selected_control_group_id,
        binding_target_kind: binding_target_kind,
        binding_target_id:
          normalize_binding_target_id(
            binding_target_kind,
            socket.assigns[:binding_target_id]
          ),
        binding_target_group_ids:
          normalize_binding_target_group_ids(
            control_groups,
            socket.assigns[:binding_target_group_ids]
          ),
        binding_action:
          normalize_binding_action(socket.assigns[:binding_action])
      )

    load_selected_control_group(socket)
  end

  defp load_selected_control_group(socket) do
    selected_group =
      Enum.find(
        socket.assigns.control_groups,
        &(&1["id"] == socket.assigns.selected_control_group_id)
      )

    assign(socket,
      editing_control_group_name: false,
      control_group_name: (selected_group && selected_group["name"]) || "",
      control_group_name_draft: (selected_group && selected_group["name"]) || "",
      control_group_group_ids: (selected_group && selected_group["group_ids"]) || [],
      control_group_light_ids: (selected_group && selected_group["light_ids"]) || [],
      selected_control_group_group_id: nil,
      selected_control_group_light_id: nil
    )
  end

  defp normalize_selected_pico_id(devices, selected_id) when is_integer(selected_id) do
    if Enum.any?(devices, &(&1.id == selected_id)) do
      selected_id
    else
      nil
    end
  end

  defp normalize_selected_pico_id(_devices, _selected_id), do: nil

  defp normalize_selected_control_group_id(control_groups, selected_id)
       when is_binary(selected_id) do
    if Enum.any?(control_groups, &(&1["id"] == selected_id)) do
      selected_id
    else
      nil
    end
  end

  defp normalize_selected_control_group_id([], _selected_id), do: nil
  defp normalize_selected_control_group_id(_control_groups, _selected_id), do: nil

  defp normalize_clone_source_id(devices, %{} = selected, source_id) when is_integer(source_id) do
    if Enum.any?(devices, &(&1.id == source_id and &1.id != selected.id)) do
      source_id
    else
      normalize_clone_source_id(devices, selected, nil)
    end
  end

  defp normalize_clone_source_id(devices, %{} = selected, _source_id) do
    devices
    |> Enum.reject(&(&1.id == selected.id))
    |> List.first()
    |> case do
      nil -> nil
      pico -> pico.id
    end
  end

  defp normalize_clone_source_id(_devices, _selected, _source_id), do: nil

  defp maybe_set_pico_room(device, room_id) do
    requested_room_id = Util.parse_optional_integer(room_id)

    cond do
      Picos.configured?(device) and requested_room_id != device.room_id ->
        {:error, :config_present}

      true ->
        Picos.set_device_room(device, room_id)
    end
  end

  defp normalize_binding_target_kind("activate_scene"), do: "scene"
  defp normalize_binding_target_kind(_action), do: "control_groups"

  defp normalize_binding_target_id("scene", target_id) do
    Util.parse_optional_integer(target_id)
  end

  defp normalize_binding_target_id("control_groups", _target_id), do: nil
  defp normalize_binding_target_id(_kind, _target_id), do: nil

  defp normalize_binding_action("activate_scene"), do: "activate_scene"
  defp normalize_binding_action(action)
       when action in ["on", "off", "toggle"],
       do: action

  defp normalize_binding_action(_action), do: "toggle"

  defp normalize_binding_target_group_ids(control_groups, target_ids) when is_list(control_groups) do
    valid_group_ids = MapSet.new(Enum.map(control_groups, & &1["id"]))

    target_ids
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(valid_group_ids, &1))
  end

  defp selectable_groups(groups) do
    Enum.reject(groups, fn group ->
      Map.get(group, :enabled) == false or Map.get(group, :canonical_group_id)
    end)
  end

  defp selectable_lights(lights) do
    Enum.reject(lights, fn light ->
      Map.get(light, :enabled) == false or Map.get(light, :canonical_light_id)
    end)
  end

  defp available_control_group_lights(%{room_id: room_id}, lights, group_ids, light_ids)
       when is_integer(room_id) and is_list(lights) do
    covered_light_ids = covered_control_group_light_ids(room_id, group_ids, light_ids)

    Enum.reject(lights, &MapSet.member?(covered_light_ids, &1.id))
  end

  defp available_control_group_lights(_device, lights, _group_ids, light_ids)
       when is_list(lights) do
    Enum.reject(lights, &(&1.id in light_ids))
  end

  defp available_control_group_groups(%{room_id: room_id}, groups, group_ids, light_ids)
       when is_integer(room_id) and is_list(groups) do
    covered_light_ids = covered_control_group_light_ids(room_id, group_ids, light_ids)
    selected_group_ids = MapSet.new(group_ids)

    Enum.reject(groups, fn group ->
      group.id in selected_group_ids or
        available_control_group_group_light_ids(room_id, group.id, covered_light_ids) == []
    end)
  end

  defp available_control_group_groups(_device, groups, group_ids, _light_ids)
       when is_list(groups) do
    Enum.reject(groups, &(&1.id in group_ids))
  end

  defp covered_control_group_light_ids(room_id, group_ids, light_ids) when is_integer(room_id) do
    room_id
    |> Hueworks.Picos.Targets.expand_room_targets(group_ids, light_ids)
    |> MapSet.new()
  end

  defp available_control_group_group_light_ids(room_id, group_id, covered_light_ids)
       when is_integer(room_id) and is_integer(group_id) do
    room_id
    |> Hueworks.Picos.Targets.expand_room_targets([group_id], [])
    |> Enum.reject(&MapSet.member?(covered_light_ids, &1))
  end

  defp control_group_picker_dom_id(kind, entities) when kind in ["group", "light"] do
    "pico-control-group-#{kind}-picker-#{control_group_picker_dom_suffix(entities)}"
  end

  defp control_group_picker_select_id(kind, entities) when kind in ["group", "light"] do
    "pico-control-group-#{kind}-select-#{control_group_picker_dom_suffix(entities)}"
  end

  defp control_group_picker_dom_suffix(entities) when is_list(entities) do
    entities
    |> Enum.map_join("-", &Integer.to_string(&1.id))
    |> case do
      "" -> "empty"
      suffix -> suffix
    end
  end

  defp persist_selected_control_group(socket) do
    case {socket.assigns.selected_pico, socket.assigns.selected_control_group_id} do
      {%{} = device, group_id} when is_binary(group_id) ->
        attrs = %{
          "id" => group_id,
          "name" => socket.assigns.control_group_name,
          "group_ids" => socket.assigns.control_group_group_ids,
          "light_ids" => socket.assigns.control_group_light_ids
        }

        case Picos.save_control_group(device, attrs) do
          {:ok, updated} ->
            socket
            |> assign(save_status: nil, save_error: nil)
            |> reload_from_devices(Picos.list_devices_for_bridge(socket.assigns.bridge.id), updated.id)
            |> select_control_group(group_id)

          {:error, :invalid_targets} ->
            assign(
              socket,
              save_status: nil,
              save_error: "Control group targets must stay in the Pico room."
            )

          {:error, :invalid_name} ->
            assign(socket, save_status: nil, save_error: "Control groups need a name.")

          {:error, reason} ->
            assign(socket, save_status: nil, save_error: inspect(reason))
        end

      _ ->
        socket
    end
  end

  defp persist_selected_control_group_name(socket) do
    trimmed_name = String.trim(socket.assigns.control_group_name_draft || "")

    case {socket.assigns.selected_pico, socket.assigns.selected_control_group_id, trimmed_name} do
      {%{} = device, group_id, name} when is_binary(group_id) and name != "" ->
        attrs = %{
          "id" => group_id,
          "name" => name,
          "group_ids" => socket.assigns.control_group_group_ids,
          "light_ids" => socket.assigns.control_group_light_ids
        }

        case Picos.save_control_group(device, attrs) do
          {:ok, updated} ->
            socket
            |> assign(
              save_status: "Control group name updated.",
              save_error: nil,
              editing_control_group_name: false
            )
            |> reload_from_devices(Picos.list_devices_for_bridge(socket.assigns.bridge.id), updated.id)
            |> select_control_group(group_id)

          {:error, :invalid_targets} ->
            assign(
              socket,
              save_status: nil,
              save_error: "Control group targets must stay in the Pico room."
            )

          {:error, :invalid_name} ->
            assign(socket, save_status: nil, save_error: "Control groups need a name.")

          {:error, reason} ->
            assign(socket, save_status: nil, save_error: inspect(reason))
        end

      {_, _, ""} ->
        assign(socket, save_status: nil, save_error: "Control groups need a name.")

      _ ->
        socket
    end
  end

  defp next_control_group_name(control_groups) when is_list(control_groups) do
    existing_names =
      control_groups
      |> Enum.map(&Map.get(&1, "name"))
      |> MapSet.new()

    Stream.iterate(1, &(&1 + 1))
    |> Enum.find_value(fn number ->
      name = "Control Group #{number}"

      if MapSet.member?(existing_names, name), do: nil, else: name
    end)
  end

  defp display_name(entity), do: Util.display_name(entity)

  defp display_name_value(%{display_name: display_name}) when is_binary(display_name),
    do: display_name

  defp display_name_value(_entity), do: ""
  defp pico_config_locked?(%{} = device), do: Picos.configured?(device)
  defp pico_config_locked?(_device), do: false

  defp auto_detected_room_option_label(device, rooms) do
    case auto_detected_room(device, rooms) do
      %{display_name: display_name} when is_binary(display_name) and display_name != "" ->
        "#{display_name} (Auto-Detected)"

      %{name: name} when is_binary(name) ->
        "#{name} (Auto-Detected)"

      nil ->
        "-"
    end
  end

  defp no_auto_detected_room?(device), do: is_nil(Picos.auto_detected_room_id(device))
  defp room_scope_clear_disabled?(%{room_id: nil}), do: true
  defp room_scope_clear_disabled?(_device), do: false

  defp auto_detected_room(device, rooms) when is_list(rooms) do
    detected_room_id = Picos.auto_detected_room_id(device)
    Enum.find(rooms, &(&1.id == detected_room_id))
  end

  attr(:label, :string, required: true)
  attr(:text, :string, required: true)

  defp help_tooltip(assigns) do
    ~H"""
    <div class="hw-help-wrap">
      <button
        type="button"
        class="hw-help-trigger"
        aria-label={"Explain #{@label}"}
        title={@text}
      >
        i
      </button>
      <div class="hw-help-bubble" role="tooltip">
        <%= @text %>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:help, :string, required: true)

  defp section_heading(assigns) do
    ~H"""
    <div class="hw-section-title-row">
      <h3><%= @title %></h3>
      <.help_tooltip label={@title} text={@help} />
    </div>
    """
  end

  defp valid_learning_binding?(
         %{"action" => action, "target_kind" => "control_groups", "target_ids" => target_ids},
         control_groups,
         _room_scenes
       )
       when action in ["on", "off", "toggle"] and is_list(target_ids) do
    available_group_ids = MapSet.new(Enum.map(control_groups, & &1["id"]))
    target_ids != [] and Enum.all?(target_ids, &MapSet.member?(available_group_ids, &1))
  end

  defp valid_learning_binding?(
         %{"action" => "activate_scene", "target_kind" => "scene", "target_id" => target_id},
         _control_groups,
         room_scenes
       )
       when is_integer(target_id) do
    Enum.any?(room_scenes, &(&1.id == target_id))
  end

  defp valid_learning_binding?(_binding, _control_groups, _room_scenes), do: false

  defp current_binding(socket) do
    %{
      "action" => socket.assigns.binding_action,
      "target_kind" => socket.assigns.binding_target_kind,
      "target_id" => socket.assigns.binding_target_id,
      "target_ids" => socket.assigns.binding_target_group_ids
    }
  end

  defp select_control_group(socket, id) do
    socket
    |> assign(selected_control_group_id: to_string(id))
    |> load_selected_control_group()
  end

  defp deselect_control_group(socket) do
    socket
    |> assign(selected_control_group_id: nil)
    |> load_selected_control_group()
  end

  defp pico_show_path(bridge_id, pico_id) when is_integer(pico_id),
    do: "/config/bridge/#{bridge_id}/picos/#{pico_id}"

  defp pico_show_path(bridge_id, _pico_id), do: pico_index_path(bridge_id)

  defp pico_index_path(bridge_id), do: "/config/bridge/#{bridge_id}/picos"

  defp reply_with_save_notice(socket) do
    socket =
      case {socket.assigns[:save_status], socket.assigns[:save_error]} do
        {message, _} when is_binary(message) ->
          socket
          |> assign(save_status: nil, save_error: nil)
          |> clear_flash(:error)
          |> put_flash(:info, message)

        {_, message} when is_binary(message) ->
          socket
          |> assign(save_status: nil, save_error: nil)
          |> clear_flash(:info)
          |> put_flash(:error, message)

        _ ->
          socket
      end

    {:noreply, socket}
  end
end
