defmodule Hueworks.Control.Group do
  @moduledoc """
  Dispatcher for group control commands.
  """

  alias Hueworks.Control.Group.{Caseta, HomeAssistant, Hue}

  def on(group), do: dispatch(group, :on)
  def off(group), do: dispatch(group, :off)
  def set_state(group, desired) when is_map(desired), do: dispatch(group, {:set_state, desired})
  def set_brightness(group, level), do: dispatch(group, {:brightness, level})
  def set_color_temp(group, kelvin), do: dispatch(group, {:color_temp, kelvin})
  def set_color(group, hs), do: dispatch(group, {:color, hs})

  defp dispatch(%{source: :hue} = group, action), do: Hue.handle(group, action)
  defp dispatch(%{source: :caseta} = group, action), do: Caseta.handle(group, action)
  defp dispatch(%{source: :ha} = group, action), do: HomeAssistant.handle(group, action)
  defp dispatch(_group, _action), do: {:error, :unsupported}
end
