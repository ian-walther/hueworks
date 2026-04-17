defmodule Hueworks.Picos.Config do
  @moduledoc false

  alias Hueworks.Picos.Bindings
  alias Hueworks.Picos.Clone
  alias Hueworks.Picos.ControlGroups
  alias Hueworks.Picos.Devices
  alias Hueworks.Repo
  alias Hueworks.Schemas.{PicoButton, PicoDevice}

  def clone_device_config(%PicoDevice{} = destination, %PicoDevice{} = source) do
    Clone.clone_device_config(destination, source)
  end

  def save_control_group(%PicoDevice{} = device, attrs) when is_map(attrs) do
    ControlGroups.save(device, attrs)
  end

  def delete_control_group(%PicoDevice{} = device, group_id) when is_binary(group_id) do
    ControlGroups.delete(device, group_id)
  end

  def assign_button_binding(%PicoDevice{} = device, button_source_id, attrs)
      when is_binary(button_source_id) and is_map(attrs) do
    Bindings.assign_button_binding(device, button_source_id, attrs)
  end

  def clear_button_binding(%PicoButton{} = button) do
    Bindings.clear_button_binding(button)
  end

  def clear_device_config(%PicoDevice{} = device) do
    device = Devices.get(device.id)
    detected_room_id = Devices.auto_detected_room_id(device)

    Repo.transaction(fn ->
      device
      |> PicoDevice.changeset(%{
        room_id: detected_room_id,
        metadata:
          (device.metadata || %{})
          |> Map.put("room_override", false)
          |> Map.put("control_groups", [])
          |> Map.drop(["preset", "primary", "secondary"])
      })
      |> Repo.update!()

      Enum.each(device.buttons, fn button ->
        button
        |> Ecto.Changeset.change(%{
          action_type: nil,
          enabled: true,
          metadata: Map.drop(button.metadata || %{}, ["preset"])
        })
        |> Ecto.Changeset.put_embed(:action_config, nil)
        |> Repo.update!()
      end)
    end)

    {:ok, Devices.get(device.id)}
  end

  def configured?(%PicoDevice{} = device) do
    device = ensure_buttons_loaded(device)
    ControlGroups.list_for_device(device) != [] or Enum.any?(device.buttons, &is_binary(&1.action_type))
  end

  def save_five_button_preset(%PicoDevice{} = device, attrs) when is_map(attrs) do
    Bindings.save_five_button_preset(device, attrs)
  end

  def save_five_button_preset(_device, _attrs), do: {:error, :invalid_device}

  defp ensure_buttons_loaded(%PicoDevice{buttons: %Ecto.Association.NotLoaded{}, id: id}) do
    Devices.get(id)
  end

  defp ensure_buttons_loaded(%PicoDevice{} = device), do: device
end
