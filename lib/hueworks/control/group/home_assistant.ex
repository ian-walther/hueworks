defmodule Hueworks.Control.Group.HomeAssistant do
  @moduledoc false

  alias Hueworks.Control.{HomeAssistantBridge, HomeAssistantClient}
  alias Hueworks.Kelvin

  def handle(group, action) do
    with {:ok, host, token} <- HomeAssistantBridge.credentials_for(group),
         {service, payload} <- action_payload(action, group),
         {:ok, _resp} <- HomeAssistantClient.request(host, token, service, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp action_payload(:on, group), do: {"turn_on", %{"entity_id" => group.source_id}}
  defp action_payload(:off, group), do: {"turn_off", %{"entity_id" => group.source_id}}

  defp action_payload({:brightness, level}, group) do
    {"turn_on", %{"entity_id" => group.source_id, "brightness" => percent_to_brightness(level)}}
  end

  defp action_payload({:color_temp, kelvin}, group) do
    kelvin = Kelvin.map_for_control(group, kelvin)
    {"turn_on", %{"entity_id" => group.source_id, "color_temp_kelvin" => round(kelvin)}}
  end

  defp action_payload({:color, {h, s}}, group) do
    {"turn_on", %{"entity_id" => group.source_id, "hs_color" => [round(h), round(s)]}}
  end

  defp action_payload(_action, _group), do: :ignore

  defp percent_to_brightness(level) do
    level
    |> clamp(1, 100)
    |> then(fn pct -> round(pct / 100 * 255) end)
  end

  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
end
