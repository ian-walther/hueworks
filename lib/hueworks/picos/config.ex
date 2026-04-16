defmodule Hueworks.Picos.Config do
  @moduledoc false

  alias Hueworks.Picos.Bindings
  alias Hueworks.Picos.Clone
  alias Hueworks.Picos.ControlGroups
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

  def save_five_button_preset(%PicoDevice{} = device, attrs) when is_map(attrs) do
    Bindings.save_five_button_preset(device, attrs)
  end

  def save_five_button_preset(_device, _attrs), do: {:error, :invalid_device}
end
