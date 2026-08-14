defmodule Hueworks.Picos do
  @moduledoc """
  Pico sync, configuration, and runtime action helpers.
  """

  alias Hueworks.Picos.{Actions, Config, ControlGroups, Devices, Summary, Sync, Targets}

  @topic "pico_events"
  def topic, do: @topic

  defdelegate list_devices_for_bridge(bridge_id), to: Devices, as: :list_for_bridge
  defdelegate get_device(id), to: Devices, as: :get
  defdelegate sync_bridge_picos(bridge), to: Sync
  defdelegate sync_bridge_picos(bridge, raw), to: Sync
  defdelegate list_area_targets(area_id), to: Targets
  defdelegate set_device_area(device, area_id), to: Devices, as: :set_area
  defdelegate update_display_name(device, attrs), to: Devices
  defdelegate control_groups(device), to: ControlGroups, as: :list_for_device
  defdelegate clone_device_config(destination, source), to: Config
  defdelegate save_control_group(device, attrs), to: Config
  defdelegate delete_control_group(device, group_id), to: Config
  defdelegate assign_button_binding(device, button_source_id, attrs), to: Config
  defdelegate clear_button_binding(button), to: Config
  defdelegate clear_device_config(device), to: Config
  defdelegate configured?(device), to: Config
  defdelegate save_five_button_preset(device, attrs), to: Config

  def handle_button_press(bridge_id, button_source_id)
      when is_integer(bridge_id) and is_binary(button_source_id) do
    Actions.handle_button_press(bridge_id, button_source_id, @topic)
  end

  defdelegate button_slot_label(device, slot_index), to: Summary
  defdelegate button_binding_summary(button, device), to: Summary
  defdelegate area_override?(device), to: Devices
  defdelegate auto_detected_area_id(device), to: Devices
end
