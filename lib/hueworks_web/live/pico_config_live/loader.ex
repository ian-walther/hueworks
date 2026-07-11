defmodule HueworksWeb.PicoConfigLive.Loader do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias Hueworks.Picos
  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias HueworksWeb.PicoConfigLive.{BindingEditor, ControlGroupEditor}

  def load_page(socket, bridge, pico_id) do
    devices = Picos.list_devices_for_bridge(bridge.id)

    selected_id =
      case socket.assigns.live_action do
        :show -> normalize_selected_pico_id(devices, pico_id)
        _ -> nil
      end

    rooms = Rooms.list_rooms()

    socket
    |> assign(
      bridge: bridge,
      all_rooms: rooms,
      sync_status: :idle,
      sync_request_id: nil,
      sync_selected_pico_id: nil
    )
    |> reload_from_devices(devices, selected_id)
  end

  def reload_from_devices(socket, devices, selected_id) do
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
    binding_target_kind = BindingEditor.normalize_target_kind(socket.assigns[:binding_action])

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
          BindingEditor.normalize_target_id(
            binding_target_kind,
            socket.assigns[:binding_target_id]
          ),
        binding_target_group_ids:
          BindingEditor.normalize_target_group_ids(
            control_groups,
            socket.assigns[:binding_target_group_ids]
          ),
        binding_action: BindingEditor.normalize_action(socket.assigns[:binding_action])
      )

    ControlGroupEditor.load_selected(socket)
  end

  def normalize_selected_pico_id(devices, selected_id) when is_integer(selected_id) do
    if Enum.any?(devices, &(&1.id == selected_id)) do
      selected_id
    else
      nil
    end
  end

  def normalize_selected_pico_id(_devices, _selected_id), do: nil

  def normalize_selected_control_group_id(control_groups, selected_id)
      when is_binary(selected_id) do
    if Enum.any?(control_groups, &(&1["id"] == selected_id)) do
      selected_id
    else
      nil
    end
  end

  def normalize_selected_control_group_id([], _selected_id), do: nil
  def normalize_selected_control_group_id(_control_groups, _selected_id), do: nil

  def normalize_clone_source_id(devices, %{} = selected, source_id) when is_integer(source_id) do
    if Enum.any?(devices, &(&1.id == source_id and &1.id != selected.id)) do
      source_id
    else
      normalize_clone_source_id(devices, selected, nil)
    end
  end

  def normalize_clone_source_id(devices, %{} = selected, _source_id) do
    devices
    |> Enum.reject(&(&1.id == selected.id))
    |> List.first()
    |> case do
      nil -> nil
      pico -> pico.id
    end
  end

  def normalize_clone_source_id(_devices, _selected, _source_id), do: nil

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
end
