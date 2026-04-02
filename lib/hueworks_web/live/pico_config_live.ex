defmodule HueworksWeb.PicoConfigLive do
  use Phoenix.LiveView

  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Rooms
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
       all_rooms: [],
       room_groups: [],
       room_lights: [],
       control_groups: [],
       new_control_group_name: "",
       selected_control_group_id: nil,
       control_group_name: "",
       control_group_group_ids: [],
       control_group_light_ids: [],
       selected_control_group_group_id: nil,
       selected_control_group_light_id: nil,
       binding_target_kind: "all_groups",
       binding_target_id: nil,
       binding_action: "toggle",
       learning_binding: nil,
       save_status: nil,
       save_error: nil
     )}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
    bridge_id = Util.parse_id(id)
    pico_id = Util.parse_id(params["pico_id"])

    case Repo.get(Bridge, bridge_id) do
      %Bridge{type: :caseta} = bridge ->
        {:noreply, load_page(socket, bridge, pico_id)}

      _ ->
        {:noreply, push_navigate(socket, to: "/config")}
    end
  end

  def handle_event("sync_picos", _params, socket) do
    case Picos.sync_bridge_picos(socket.assigns.bridge) do
      {:ok, devices} ->
        selected_id = selected_pico_id(socket.assigns.selected_pico, devices)

        {:noreply,
         socket
         |> assign(save_status: "Picos synced.", save_error: nil)
         |> reload_from_devices(devices, selected_id)}

      {:error, reason} ->
        {:noreply, assign(socket, save_status: nil, save_error: inspect(reason))}
    end
  end

  def handle_event("select_pico", %{"id" => id}, socket) do
    pico_id = Util.parse_id(id)
    {:noreply, push_patch(socket, to: pico_path(socket.assigns.bridge.id, pico_id))}
  end

  def handle_event("save_room_override", %{"room_id" => room_id}, socket) do
    case socket.assigns.selected_pico do
      nil ->
        {:noreply, assign(socket, save_status: nil, save_error: "Select a Pico first.")}

      device ->
        case Picos.set_device_room(device, room_id) do
          {:ok, updated} ->
            devices = Picos.list_devices_for_bridge(socket.assigns.bridge.id)

            {:noreply,
             socket
             |> assign(save_status: "Pico room updated.", save_error: nil)
             |> reload_from_devices(devices, updated.id)}

          {:error, reason} ->
            {:noreply, assign(socket, save_status: nil, save_error: inspect(reason))}
        end
    end
  end

  def handle_event("update_new_control_group", %{"name" => name}, socket) do
    {:noreply, assign(socket, new_control_group_name: name)}
  end

  def handle_event("create_control_group", %{"name" => name}, socket) do
    case socket.assigns.selected_pico do
      nil ->
        {:noreply, assign(socket, save_status: nil, save_error: "Select a Pico first.")}

      device ->
        case Picos.save_control_group(device, %{
               "name" => name,
               "group_ids" => [],
               "light_ids" => []
             }) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(
               save_status: "Control group created.",
               save_error: nil,
               new_control_group_name: ""
             )
             |> reload_from_devices(
               Picos.list_devices_for_bridge(socket.assigns.bridge.id),
               updated.id
             )}

          {:error, :missing_room} ->
            {:noreply, assign(socket, save_status: nil, save_error: "Set the Pico room first.")}

          {:error, :invalid_name} ->
            {:noreply,
             assign(socket, save_status: nil, save_error: "Control groups need a name.")}

          {:error, reason} ->
            {:noreply, assign(socket, save_status: nil, save_error: inspect(reason))}
        end
    end
  end

  def handle_event("select_control_group", %{"id" => id}, socket) do
    {:noreply, select_control_group(socket, id)}
  end

  def handle_event("edit_control_group_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, control_group_name: name)}
  end

  def handle_event("select_control_group_entity", %{"entity" => entity, "id" => id}, socket) do
    key =
      case entity do
        "group" -> :selected_control_group_group_id
        "light" -> :selected_control_group_light_id
      end

    {:noreply, assign(socket, key, Util.parse_optional_integer(id))}
  end

  def handle_event("add_control_group_entity", %{"entity" => entity}, socket) do
    {selection_key, list_key} =
      case entity do
        "group" -> {:selected_control_group_group_id, :control_group_group_ids}
        "light" -> {:selected_control_group_light_id, :control_group_light_ids}
      end

    selected_id = socket.assigns[selection_key]

    socket =
      if is_integer(selected_id) do
        socket
        |> assign(list_key, Enum.uniq(socket.assigns[list_key] ++ [selected_id]))
        |> assign(selection_key, nil)
      else
        socket
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
       assign(socket, list_key, Enum.reject(socket.assigns[list_key], &(&1 == entity_id)))
     else
       socket
     end}
  end

  def handle_event("save_control_group", _params, socket) do
    case {socket.assigns.selected_pico, socket.assigns.selected_control_group_id} do
      {nil, _} ->
        {:noreply, assign(socket, save_status: nil, save_error: "Select a Pico first.")}

      {_, nil} ->
        {:noreply,
         assign(socket, save_status: nil, save_error: "Select or create a control group first.")}

      {device, group_id} ->
        attrs = %{
          "id" => group_id,
          "name" => socket.assigns.control_group_name,
          "group_ids" => socket.assigns.control_group_group_ids,
          "light_ids" => socket.assigns.control_group_light_ids
        }

        case Picos.save_control_group(device, attrs) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(save_status: "Control group saved.", save_error: nil)
             |> reload_from_devices(
               Picos.list_devices_for_bridge(socket.assigns.bridge.id),
               updated.id
             )
             |> select_control_group(group_id)}

          {:error, :invalid_targets} ->
            {:noreply,
             assign(socket,
               save_status: nil,
               save_error: "Control group targets must stay in the Pico room."
             )}

          {:error, :invalid_name} ->
            {:noreply,
             assign(socket, save_status: nil, save_error: "Control groups need a name.")}

          {:error, reason} ->
            {:noreply, assign(socket, save_status: nil, save_error: inspect(reason))}
        end
    end
  end

  def handle_event("delete_control_group", %{"id" => id}, socket) do
    group_id = to_string(id)

    case socket.assigns.selected_pico do
      nil ->
        {:noreply, assign(socket, save_status: nil, save_error: "Select a Pico first.")}

      device ->
        {:ok, updated} = Picos.delete_control_group(device, group_id)

        {:noreply,
         socket
         |> assign(save_status: "Control group deleted.", save_error: nil)
         |> reload_from_devices(
           Picos.list_devices_for_bridge(socket.assigns.bridge.id),
           updated.id
         )}
    end
  end

  def handle_event("update_binding_editor", params, socket) do
    target_kind = params["target_kind"] || socket.assigns.binding_target_kind
    target_id = params["target_id"] || socket.assigns.binding_target_id
    action = params["action"] || socket.assigns.binding_action

    {:noreply,
     assign(socket,
       binding_target_kind: target_kind,
       binding_target_id: normalize_binding_target_id(target_kind, target_id),
       binding_action: action
     )}
  end

  def handle_event("start_button_learning", _params, socket) do
    learning_binding = %{
      "action" => socket.assigns.binding_action,
      "target_kind" => socket.assigns.binding_target_kind,
      "target_id" => socket.assigns.binding_target_id
    }

    with %{} <- socket.assigns.selected_pico,
         true <- valid_learning_binding?(learning_binding, socket.assigns.control_groups) do
      {:noreply,
       assign(socket,
         learning_binding: learning_binding,
         save_status: "Press a button on this Pico to assign the selected action.",
         save_error: nil
       )}
    else
      nil ->
        {:noreply, assign(socket, save_status: nil, save_error: "Select a Pico first.")}

      false ->
        {:noreply,
         assign(socket,
           save_status: nil,
           save_error: "Choose an action and a target before starting button learning."
         )}
    end
  end

  def handle_event("cancel_button_learning", _params, socket) do
    {:noreply,
     assign(socket,
       learning_binding: nil,
       save_status: "Button learning cancelled.",
       save_error: nil
     )}
  end

  def handle_event("clear_button_binding", %{"id" => id}, socket) do
    button_id = Util.parse_id(id)

    case Enum.find(socket.assigns.selected_pico.buttons, &(&1.id == button_id)) do
      nil ->
        {:noreply, socket}

      button ->
        case Picos.clear_button_binding(button) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> assign(save_status: "Button binding cleared.", save_error: nil)
             |> reload_from_devices(
               Picos.list_devices_for_bridge(socket.assigns.bridge.id),
               socket.assigns.selected_pico.id
             )}

          {:error, reason} ->
            {:noreply, assign(socket, save_status: nil, save_error: inspect(reason))}
        end
    end
  end

  def handle_info({:pico_button_press, pico_device_id, button_source_id}, socket) do
    if Enum.any?(socket.assigns.pico_devices, &(&1.id == pico_device_id)) do
      socket =
        socket
        |> push_patch(to: pico_path(socket.assigns.bridge.id, pico_device_id))

      if socket.assigns.selected_pico && socket.assigns.selected_pico.id == pico_device_id &&
           socket.assigns.learning_binding do
        case Picos.assign_button_binding(
               socket.assigns.selected_pico,
               button_source_id,
               socket.assigns.learning_binding
             ) do
          {:ok, _button} ->
            {:noreply,
             socket
             |> assign(
               learning_binding: nil,
               save_status: "Assigned action to the pressed Pico button.",
               save_error: nil
             )
             |> reload_from_devices(
               Picos.list_devices_for_bridge(socket.assigns.bridge.id),
               pico_device_id
             )}

          {:error, reason} ->
            {:noreply,
             assign(
               socket,
               learning_binding: nil,
               save_status: nil,
               save_error: "Failed to assign pressed button: #{inspect(reason)}"
             )}
        end
      else
        {:noreply, assign(socket, save_status: "Detected Pico button press.", save_error: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_page(socket, bridge, pico_id) do
    devices = Picos.list_devices_for_bridge(bridge.id)
    selected_id = normalize_selected_pico_id(devices, pico_id)
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

    control_groups = if selected, do: Picos.control_groups(selected), else: []

    selected_control_group_id =
      normalize_selected_control_group_id(
        control_groups,
        socket.assigns[:selected_control_group_id]
      )

    socket =
      assign(socket,
        pico_devices: devices,
        selected_pico: selected,
        room_groups: groups,
        room_lights: lights,
        control_groups: control_groups,
        selected_control_group_id: selected_control_group_id,
        binding_target_kind:
          normalize_binding_target_kind(socket.assigns[:binding_target_kind], control_groups),
        binding_target_id:
          normalize_binding_target_id(
            normalize_binding_target_kind(socket.assigns[:binding_target_kind], control_groups),
            socket.assigns[:binding_target_id]
          )
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
      control_group_name: (selected_group && selected_group["name"]) || "",
      control_group_group_ids: (selected_group && selected_group["group_ids"]) || [],
      control_group_light_ids: (selected_group && selected_group["light_ids"]) || [],
      selected_control_group_group_id: nil,
      selected_control_group_light_id: nil
    )
  end

  defp selected_pico_id(nil, devices), do: normalize_selected_pico_id(devices, nil)
  defp selected_pico_id(device, _devices), do: device.id

  defp normalize_selected_pico_id(devices, selected_id) when is_integer(selected_id) do
    if Enum.any?(devices, &(&1.id == selected_id)) do
      selected_id
    else
      normalize_selected_pico_id(devices, nil)
    end
  end

  defp normalize_selected_pico_id([first | _], _selected_id), do: first.id
  defp normalize_selected_pico_id([], _selected_id), do: nil

  defp normalize_selected_control_group_id(control_groups, selected_id)
       when is_binary(selected_id) do
    if Enum.any?(control_groups, &(&1["id"] == selected_id)) do
      selected_id
    else
      normalize_selected_control_group_id(control_groups, nil)
    end
  end

  defp normalize_selected_control_group_id([first | _], _selected_id), do: first["id"]
  defp normalize_selected_control_group_id([], _selected_id), do: nil

  defp normalize_binding_target_kind("control_group", control_groups) when control_groups != [],
    do: "control_group"

  defp normalize_binding_target_kind(_kind, _control_groups), do: "all_groups"

  defp normalize_binding_target_id("control_group", target_id) when is_binary(target_id),
    do: target_id

  defp normalize_binding_target_id("control_group", _target_id), do: nil
  defp normalize_binding_target_id(_kind, _target_id), do: nil

  defp valid_learning_binding?(
         %{"action" => action, "target_kind" => "all_groups"},
         control_groups
       )
       when action in ["on", "off", "toggle"],
       do: control_groups != []

  defp valid_learning_binding?(
         %{"action" => action, "target_kind" => "control_group", "target_id" => target_id},
         control_groups
       )
       when action in ["on", "off", "toggle"] and is_binary(target_id) do
    Enum.any?(control_groups, &(&1["id"] == target_id))
  end

  defp valid_learning_binding?(_binding, _control_groups), do: false

  defp select_control_group(socket, id) do
    socket
    |> assign(selected_control_group_id: to_string(id))
    |> load_selected_control_group()
  end

  defp pico_path(bridge_id, pico_id) when is_integer(pico_id),
    do: "/config/bridge/#{bridge_id}/picos?pico_id=#{pico_id}"

  defp pico_path(bridge_id, _pico_id), do: "/config/bridge/#{bridge_id}/picos"
end
