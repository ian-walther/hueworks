defmodule Hueworks.Control.Light do
  @moduledoc """
  Dispatcher for light control commands.
  """

  alias Hueworks.Control.Light.{Caseta, HomeAssistant, Hue}

  def on(light), do: dispatch(light, :on)
  def off(light), do: dispatch(light, :off)
  def set_brightness(light, level), do: dispatch(light, {:brightness, level})
  def set_color_temp(light, kelvin), do: dispatch(light, {:color_temp, kelvin})
  def set_color(light, hs), do: dispatch(light, {:color, hs})

  defp dispatch(%{source: :hue} = light, action), do: Hue.handle(light, action)
  defp dispatch(%{source: :caseta} = light, action), do: Caseta.handle(light, action)
  defp dispatch(%{source: :ha} = light, action), do: HomeAssistant.handle(light, action)
  defp dispatch(_light, _action), do: {:error, :unsupported}
end
