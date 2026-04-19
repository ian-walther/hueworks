defmodule Hueworks.Picos.Summary do
  @moduledoc false

  alias Hueworks.Picos.ControlGroups
  alias Hueworks.Picos.Targets
  alias Hueworks.Schemas.PicoButton.ActionConfig, as: StoredActionConfig
  alias Hueworks.Schemas.{PicoButton, PicoDevice}

  def button_slot_label(_device, slot_index), do: "Button #{slot_index + 1}"

  def button_binding_summary(%PicoButton{} = button, %PicoDevice{} = device) do
    case {button.action_type, PicoButton.action_config_struct(button)} do
      {nil, _config} ->
        "Not assigned"

      {action_type, %StoredActionConfig{target_kind: :control_groups, target_ids: target_ids}} ->
        target_name =
          device
          |> control_groups()
          |> multi_group_binding_label(target_ids)

        "#{binding_action_label(action_type)} #{target_name}"

      {action_type, %StoredActionConfig{target_kind: :scene} = config} ->
        target_id = StoredActionConfig.target_id(config)
        "#{binding_action_label(action_type)} #{Targets.scene_name_for_target(target_id, device.room_id)}"

      {action_type, %StoredActionConfig{light_ids: light_ids}} when light_ids != [] ->
        "#{binding_action_label(action_type)} Custom Lights"

      {action_type, _config} ->
        binding_action_label(action_type)
    end
  end

  defp control_groups(%PicoDevice{} = device) do
    device
    |> Map.get(:metadata, %{})
    |> Map.get("control_groups", [])
    |> ControlGroups.normalize()
  end

  defp multi_group_binding_label(control_groups, target_ids) when is_list(target_ids) do
    names =
      target_ids
      |> Enum.map(fn target_id ->
        Enum.find_value(control_groups, fn group ->
          if group["id"] == target_id, do: group["name"], else: nil
        end)
      end)
      |> Enum.reject(&is_nil/1)

    case names do
      [] -> "Unknown Groups"
      [name] -> name
      [first, second] -> "#{first} + #{second}"
      [first | rest] -> "#{first} + #{length(rest)} more"
    end
  end

  defp binding_action_label("turn_on"), do: "Turn On"
  defp binding_action_label("turn_off"), do: "Turn Off"
  defp binding_action_label("toggle_any_on"), do: "Toggle"
  defp binding_action_label("activate_scene"), do: "Activate Scene"
  defp binding_action_label(action), do: to_string(action)
end
