defmodule HueworksWeb.PicoConfigLive do
  use Phoenix.LiveView

  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util
  alias HueworksWeb.PicoConfigLive.{BindingEditor, ControlGroupEditor, Loader}

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
       sync_status: :idle,
       sync_request_id: nil,
       sync_selected_pico_id: nil,
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
    case socket.assigns.sync_request_id do
      request_id when is_integer(request_id) ->
        {:noreply, socket}

      _ ->
        request_id = System.unique_integer([:positive])
        bridge = socket.assigns.bridge
        selected_id = sync_selected_pico_id(socket)

        socket =
          assign(socket,
            sync_status: :syncing,
            sync_request_id: request_id,
            sync_selected_pico_id: selected_id,
            save_status: nil,
            save_error: nil
          )

        {:noreply,
         start_async(socket, {:sync_picos, request_id}, fn ->
           Picos.sync_bridge_picos(bridge)
         end)}
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
               "name" => ControlGroupEditor.next_name(socket.assigns.control_groups),
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
            |> ControlGroupEditor.select(group_id)
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
       ControlGroupEditor.deselect(socket)
     else
       ControlGroupEditor.select(socket, id)
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
    |> ControlGroupEditor.persist_selected_name()
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
        |> ControlGroupEditor.persist_selected()
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
       |> ControlGroupEditor.persist_selected()
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
            |> ControlGroupEditor.select(group_id)
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
    {:noreply, assign(socket, BindingEditor.update_assigns(socket.assigns, params))}
  end

  def handle_event("start_button_learning", _params, socket) do
    learning_binding = BindingEditor.current_binding(socket.assigns)

    with %{} <- socket.assigns.selected_pico,
         true <-
           BindingEditor.valid_learning_binding?(
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
    binding = BindingEditor.current_binding(socket.assigns)

    with %{} = device <- socket.assigns.selected_pico,
         %{} = button <- Enum.find(device.buttons, &(&1.id == button_id)),
         true <-
           BindingEditor.valid_learning_binding?(
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

  def handle_async({:sync_picos, request_id}, {:ok, result}, socket) do
    if socket.assigns.sync_request_id == request_id do
      {:noreply, apply_sync_result(socket, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:sync_picos, request_id}, {:exit, reason}, socket) do
    if socket.assigns.sync_request_id == request_id do
      socket
      |> assign(
        sync_status: :idle,
        sync_request_id: nil,
        sync_selected_pico_id: nil,
        save_status: nil,
        save_error: "Pico sync failed: #{inspect(reason)}"
      )
      |> reply_with_save_notice()
    else
      {:noreply, socket}
    end
  end

  defp load_page(socket, bridge, pico_id) do
    Loader.load_page(socket, bridge, pico_id)
  end

  defp reload_from_devices(socket, devices, selected_id) do
    Loader.reload_from_devices(socket, devices, selected_id)
  end

  defp apply_sync_result(socket, {:ok, devices}) do
    selected_id = socket.assigns.sync_selected_pico_id

    socket
    |> assign(
      sync_status: :idle,
      sync_request_id: nil,
      sync_selected_pico_id: nil,
      save_status: "Picos synced.",
      save_error: nil
    )
    |> reload_from_devices(devices, selected_id)
    |> clear_flash(:error)
    |> put_flash(:info, "Picos synced.")
  end

  defp apply_sync_result(socket, {:error, reason}) do
    socket
    |> assign(
      sync_status: :idle,
      sync_request_id: nil,
      sync_selected_pico_id: nil,
      save_status: nil,
      save_error: inspect(reason)
    )
    |> clear_flash(:info)
    |> put_flash(:error, inspect(reason))
  end

  defp apply_sync_result(socket, other) do
    apply_sync_result(socket, {:error, other})
  end

  defp sync_selected_pico_id(socket) do
    case socket.assigns.live_action do
      :show -> socket.assigns.selected_pico && socket.assigns.selected_pico.id
      _ -> nil
    end
  end

  defp maybe_set_pico_room(device, room_id) do
    requested_room_id = Util.parse_optional_integer(room_id)

    cond do
      Picos.configured?(device) and requested_room_id != device.room_id ->
        {:error, :config_present}

      true ->
        Picos.set_device_room(device, room_id)
    end
  end

  defp available_control_group_lights(%{room_id: room_id}, lights, group_ids, light_ids)
       when is_integer(room_id) and is_list(lights) do
    ControlGroupEditor.available_lights(%{room_id: room_id}, lights, group_ids, light_ids)
  end

  defp available_control_group_lights(_device, lights, _group_ids, light_ids)
       when is_list(lights) do
    ControlGroupEditor.available_lights(nil, lights, [], light_ids)
  end

  defp available_control_group_groups(%{room_id: room_id}, groups, group_ids, light_ids)
       when is_integer(room_id) and is_list(groups) do
    ControlGroupEditor.available_groups(%{room_id: room_id}, groups, group_ids, light_ids)
  end

  defp available_control_group_groups(_device, groups, group_ids, _light_ids)
       when is_list(groups) do
    ControlGroupEditor.available_groups(nil, groups, group_ids, [])
  end

  defp control_group_picker_dom_id(kind, entities) when kind in ["group", "light"] do
    ControlGroupEditor.picker_dom_id(kind, entities)
  end

  defp control_group_picker_select_id(kind, entities) when kind in ["group", "light"] do
    ControlGroupEditor.picker_select_id(kind, entities)
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

  defp pico_show_path(bridge_id, pico_id) when is_integer(pico_id),
    do: "/config/bridges/#{bridge_id}/picos/#{pico_id}"

  defp pico_show_path(bridge_id, _pico_id), do: pico_index_path(bridge_id)

  defp pico_index_path(bridge_id), do: "/config/bridges/#{bridge_id}/picos"

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
