defmodule Hueworks.Picos do
  @moduledoc """
  Pico sync, configuration, and runtime action helpers.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Picos.{Actions, Config, Sync}
  alias Hueworks.Picos.Targets
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, Light, PicoButton, PicoDevice}
  alias Hueworks.Util

  @topic "pico_events"
  def topic, do: @topic

  def list_devices_for_bridge(bridge_id) when is_integer(bridge_id) do
    Repo.all(
      from(pd in PicoDevice,
        where: pd.bridge_id == ^bridge_id,
        order_by: [asc: pd.name]
      )
    )
    |> Repo.preload([:room, buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])])
  end

  def get_device(id) when is_integer(id) do
    PicoDevice
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      device ->
        Repo.preload(device, [
          :room,
          buttons: from(pb in PicoButton, order_by: [asc: pb.button_number])
        ])
    end
  end

  def sync_bridge_picos(%Bridge{type: :caseta} = bridge) do
    Sync.sync_bridge_picos(bridge)
  end

  def sync_bridge_picos(%Bridge{} = bridge, raw) when is_map(raw) do
    Sync.sync_bridge_picos(bridge, raw)
  end

  def list_room_targets(room_id) when is_integer(room_id) do
    lights =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id and is_nil(l.canonical_light_id),
          order_by: [asc: l.name]
        )
      )

    groups =
      Repo.all(
        from(g in Group,
          where: g.room_id == ^room_id and is_nil(g.canonical_group_id),
          order_by: [asc: g.name]
        )
      )

    {groups, lights}
  end

  def set_device_room(%PicoDevice{} = device, room_id) do
    detected_room_id = auto_detected_room_id(device)
    room_id = Util.parse_optional_integer(room_id)
    metadata = device.metadata || %{}

    attrs =
      case room_id do
        nil ->
          %{
            room_id: detected_room_id,
            metadata:
              metadata
              |> Map.put("room_override", false)
          }

        room_id ->
          %{
            room_id: room_id,
            metadata:
              metadata
              |> Map.put("room_override", true)
          }
      end

    device
    |> PicoDevice.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, get_device(updated.id)}
      other -> other
    end
  end

  def control_groups(%PicoDevice{} = device) do
    device
    |> Map.get(:metadata, %{})
    |> Map.get("control_groups", [])
    |> normalize_control_groups()
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

  def save_five_button_preset(%PicoDevice{} = device, attrs) when is_map(attrs) do
    Config.save_five_button_preset(device, attrs)
  end

  def save_five_button_preset(_device, _attrs), do: {:error, :invalid_device}

  def handle_button_press(bridge_id, button_source_id)
      when is_integer(bridge_id) and is_binary(button_source_id) do
    Actions.handle_button_press(bridge_id, button_source_id, @topic)
  end

  def button_slot_label(_device, slot_index), do: "Button #{slot_index + 1}"

  def button_binding_summary(%PicoButton{} = button, %PicoDevice{} = device) do
    case {button.action_type, button.action_config || %{}} do
      {nil, _} ->
        "Not assigned"

      {action_type, %{"target_kind" => "all_groups"}} ->
        "#{binding_action_label(action_type)} All Control Groups"

      {action_type, %{"target_kind" => "control_group", "target_id" => target_id}} ->
        target_name =
          device
          |> control_groups()
          |> Enum.find_value("Unknown Group", fn group ->
            if group["id"] == target_id, do: group["name"], else: nil
          end)

        "#{binding_action_label(action_type)} #{target_name}"

      {action_type, %{"target_kind" => "scene", "target_id" => target_id}} ->
        "#{binding_action_label(action_type)} #{scene_name_for_target(Util.parse_optional_integer(target_id), device.room_id)}"

      {action_type, config} when is_map_key(config, "light_ids") ->
        "#{binding_action_label(action_type)} Custom Lights"

      {action_type, _config} ->
        binding_action_label(action_type)
    end
  end

  def room_override?(%PicoDevice{} = device) do
    Map.get(device.metadata || %{}, "room_override") == true
  end

  def auto_detected_room_id(%PicoDevice{} = device) do
    (device.metadata || %{})
    |> Map.get("detected_room_id")
    |> Util.parse_optional_integer()
  end

  defp binding_action_label("turn_on"), do: "Turn On"
  defp binding_action_label("turn_off"), do: "Turn Off"
  defp binding_action_label("toggle_any_on"), do: "Toggle"
  defp binding_action_label("activate_scene"), do: "Activate Scene"
  defp binding_action_label(action), do: to_string(action)

  defp normalize_control_groups(groups) when is_list(groups) do
    groups
    |> Enum.flat_map(fn
      %{} = group ->
        id = Map.get(group, "id") || Map.get(group, :id)
        name = Map.get(group, "name") || Map.get(group, :name)

        if is_binary(id) and is_binary(name) and String.trim(name) != "" do
          [
            %{
              "id" => id,
              "name" => String.trim(name),
              "group_ids" =>
                Targets.normalize_integer_ids(
                  Map.get(group, "group_ids") || Map.get(group, :group_ids)
                ),
              "light_ids" =>
                Targets.normalize_integer_ids(
                  Map.get(group, "light_ids") || Map.get(group, :light_ids)
                )
            }
          ]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp normalize_control_groups(_groups), do: []

  defp scene_name_for_target(scene_id, room_id),
    do: Targets.scene_name_for_target(scene_id, room_id)
end
