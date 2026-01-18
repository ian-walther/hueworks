defmodule Hueworks.Control.Light.HomeAssistant do
  @moduledoc false

  alias Hueworks.Control.{HomeAssistantBridge, HomeAssistantClient}

  def handle(light, action) do
    with {:ok, host, token} <- HomeAssistantBridge.credentials_for(light),
         {service, payload} <- action_payload(action, light),
         {:ok, _resp} <- HomeAssistantClient.request(host, token, service, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp action_payload(:on, light), do: {"turn_on", %{"entity_id" => light.source_id}}
  defp action_payload(:off, light), do: {"turn_off", %{"entity_id" => light.source_id}}

  defp action_payload({:brightness, level}, light) do
    {"turn_on", %{"entity_id" => light.source_id, "brightness" => percent_to_brightness(level)}}
  end

  defp action_payload({:color_temp, kelvin}, light) do
    {"turn_on", %{"entity_id" => light.source_id, "color_temp_kelvin" => round(kelvin)}}
  end

  defp action_payload({:color, {h, s}}, light) do
    {"turn_on", %{"entity_id" => light.source_id, "hs_color" => [round(h), round(s)]}}
  end

  defp action_payload(_action, _light), do: :ignore

  defp percent_to_brightness(level) do
    level
    |> clamp(1, 100)
    |> then(fn pct -> round(pct / 100 * 255) end)
  end

  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
end
