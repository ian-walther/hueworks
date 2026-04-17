defmodule Hueworks.Picos do
  @moduledoc """
  Pico sync, configuration, and runtime action helpers.
  """

  alias Hueworks.Picos.{Actions, Config, ControlGroups, Devices, Summary, Sync, Targets}
  alias Hueworks.Schemas.{Bridge, PicoButton, PicoDevice}

  @topic "pico_events"
  def topic, do: @topic

  def list_devices_for_bridge(bridge_id) when is_integer(bridge_id) do
    Devices.list_for_bridge(bridge_id)
  end

  def get_device(id) when is_integer(id) do
    Devices.get(id)
  end

  def sync_bridge_picos(%Bridge{type: :caseta} = bridge) do
    Sync.sync_bridge_picos(bridge)
  end

  def sync_bridge_picos(%Bridge{} = bridge, raw) when is_map(raw) do
    Sync.sync_bridge_picos(bridge, raw)
  end

  def list_room_targets(room_id) when is_integer(room_id) do
    Targets.list_room_targets(room_id)
  end

  def set_device_room(%PicoDevice{} = device, room_id) do
    Devices.set_room(device, room_id)
  end

  def update_display_name(%PicoDevice{} = device, attrs) when is_map(attrs) do
    Devices.update_display_name(device, attrs)
  end

  def update_display_name(%PicoDevice{} = device, display_name) do
    Devices.update_display_name(device, display_name)
  end

  def control_groups(%PicoDevice{} = device) do
    ControlGroups.list_for_device(device)
  end

  def clone_device_config(%PicoDevice{} = destination, %PicoDevice{} = source) do
    Config.clone_device_config(destination, source)
  end

  def save_control_group(%PicoDevice{} = device, attrs) when is_map(attrs) do
    Config.save_control_group(device, attrs)
  end

  def delete_control_group(%PicoDevice{} = device, group_id) when is_binary(group_id) do
    Config.delete_control_group(device, group_id)
  end

  def assign_button_binding(%PicoDevice{} = device, button_source_id, attrs)
      when is_binary(button_source_id) and is_map(attrs) do
    Config.assign_button_binding(device, button_source_id, attrs)
  end

  def clear_button_binding(%PicoButton{} = button) do
    Config.clear_button_binding(button)
  end

  def clear_device_config(%PicoDevice{} = device) do
    Config.clear_device_config(device)
  end

  def configured?(%PicoDevice{} = device) do
    Config.configured?(device)
  end

  def save_five_button_preset(%PicoDevice{} = device, attrs) when is_map(attrs) do
    Config.save_five_button_preset(device, attrs)
  end

  def save_five_button_preset(_device, _attrs), do: {:error, :invalid_device}

  def handle_button_press(bridge_id, button_source_id)
      when is_integer(bridge_id) and is_binary(button_source_id) do
    Actions.handle_button_press(bridge_id, button_source_id, @topic)
  end

  def button_slot_label(device, slot_index), do: Summary.button_slot_label(device, slot_index)

  def button_binding_summary(%PicoButton{} = button, %PicoDevice{} = device) do
    Summary.button_binding_summary(button, device)
  end

  def room_override?(%PicoDevice{} = device) do
    Devices.room_override?(device)
  end

  def auto_detected_room_id(%PicoDevice{} = device) do
    Devices.auto_detected_room_id(device)
  end
end
