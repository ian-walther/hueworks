defmodule Hueworks.Picos.Actions do
  @moduledoc false

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.{DesiredState, State}
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Picos
  alias Hueworks.Picos.Targets
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{PicoButton, PicoDevice}
  alias Phoenix.PubSub

  def handle_button_press(bridge_id, button_source_id, topic)
      when is_integer(bridge_id) and is_binary(button_source_id) and is_binary(topic) do
    Logger.info(
      "[pico-trace] handle_button_press_start bridge_id=#{bridge_id} button_source_id=#{inspect(button_source_id)}"
    )

    button =
      Repo.one(
        from(pb in PicoButton,
          join: pd in PicoDevice,
          on: pd.id == pb.pico_device_id,
          where: pd.bridge_id == ^bridge_id and pb.source_id == ^button_source_id,
          preload: [pico_device: pd]
        )
      )

    case button do
      nil ->
        Logger.warning(
          "[pico-trace] handle_button_press_missing_mapping bridge_id=#{bridge_id} button_source_id=#{inspect(button_source_id)}"
        )

        :ignored

      %PicoButton{} = button ->
        timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

        button
        |> PicoButton.changeset(%{last_pressed_at: timestamp})
        |> Repo.update!()

        broadcast_press(topic, button.pico_device_id, button.source_id)

        result =
          if button.enabled do
            execute_button_action(button)
          else
            Logger.info(
              "[pico-trace] handle_button_press_ignored bridge_id=#{bridge_id} button_source_id=#{inspect(button_source_id)} reason=:button_disabled"
            )

            :ignored
          end

        Logger.info(
          "[pico-trace] handle_button_press_complete bridge_id=#{bridge_id} pico_device_id=#{button.pico_device_id} button_source_id=#{inspect(button.source_id)} button_number=#{inspect(button.button_number)} slot_index=#{inspect(button.slot_index)} slot_label=#{inspect(Picos.button_slot_label(button.pico_device, button.slot_index))} binding=#{inspect(Picos.button_binding_summary(button, button.pico_device))} action_type=#{inspect(button.action_type)} action_config=#{inspect(button.action_config)} result=#{inspect(result)}"
        )

        result
    end
  end

  defp execute_button_action(%PicoButton{action_type: nil}), do: :ignored

  defp execute_button_action(%PicoButton{pico_device: %{room_id: room_id}})
       when not is_integer(room_id) do
    Logger.warning("[pico-trace] execute_button_action_ignored reason=:missing_room")
    :ignored
  end

  defp execute_button_action(%PicoButton{
         action_type: "turn_on",
         pico_device: device,
         action_config: config
       }) do
    light_ids = action_light_ids(device, config)

    Logger.info(
      "[pico-trace] execute_button_action room_id=#{device.room_id} action=:on light_ids=#{inspect(light_ids)}"
    )

    _ = ManualControl.apply_power_action(device.room_id, light_ids, :on)
    :handled
  end

  defp execute_button_action(%PicoButton{
         action_type: "turn_off",
         pico_device: device,
         action_config: config
       }) do
    light_ids = action_light_ids(device, config)

    Logger.info(
      "[pico-trace] execute_button_action room_id=#{device.room_id} action=:off light_ids=#{inspect(light_ids)}"
    )

    _ = ManualControl.apply_power_action(device.room_id, light_ids, :off)
    :handled
  end

  defp execute_button_action(%PicoButton{
         action_type: "toggle_any_on",
         pico_device: device,
         action_config: config
       }) do
    light_ids = action_light_ids(device, config)
    any_on? = Enum.any?(light_ids, &light_powered?/1)

    action = if(any_on?, do: :off, else: :on)

    Logger.info(
      "[pico-trace] execute_button_action room_id=#{device.room_id} action=#{inspect(action)} light_ids=#{inspect(light_ids)} any_on?=#{any_on?}"
    )

    _ = ManualControl.apply_power_action(device.room_id, light_ids, action)
    :handled
  end

  defp execute_button_action(%PicoButton{
         action_type: "activate_scene",
         pico_device: device,
         action_config: %{"target_kind" => "scene", "target_id" => scene_id}
       })
       when is_integer(scene_id) do
    Logger.info(
      "[pico-trace] execute_button_action room_id=#{device.room_id} action=:activate_scene scene_id=#{scene_id}"
    )

    case Scenes.activate_scene(scene_id) do
      {:ok, _diff, _updated} -> :handled
      _ -> :ignored
    end
  end

  defp execute_button_action(button) do
    Logger.info(
      "[pico-trace] execute_button_action_ignored action_type=#{inspect(button.action_type)}"
    )

    :ignored
  end

  defp action_light_ids(_device, %{"light_ids" => light_ids}) when is_list(light_ids) do
    Targets.normalize_integer_ids(light_ids)
  end

  defp action_light_ids(device, %{"target_kind" => "all_groups"}) do
    device
    |> Picos.control_groups()
    |> Enum.flat_map(&Targets.control_group_light_ids(device.room_id, &1))
    |> Enum.uniq()
  end

  defp action_light_ids(device, %{"target_kind" => "control_group", "target_id" => target_id}) do
    device
    |> Picos.control_groups()
    |> Enum.find(&(Map.get(&1, "id") == target_id))
    |> case do
      nil -> []
      group -> Targets.control_group_light_ids(device.room_id, group)
    end
  end

  defp action_light_ids(_device, _config), do: []

  defp light_powered?(light_id) do
    state = DesiredState.get(:light, light_id) || State.get(:light, light_id) || %{}
    Map.get(state, :power) == :on
  end

  defp broadcast_press(topic, pico_device_id, button_source_id) do
    PubSub.broadcast(
      Hueworks.PubSub,
      topic,
      {:pico_button_press, pico_device_id, button_source_id}
    )
  end
end
