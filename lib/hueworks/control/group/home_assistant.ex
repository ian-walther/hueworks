defmodule Hueworks.Control.Group.HomeAssistant do
  @moduledoc false

  alias Hueworks.Control.{HomeAssistantBridge, HomeAssistantClient}
  alias Hueworks.Util
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

  defp action_payload({:set_state, desired}, group) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")
    brightness = value_or_nil(desired, [:brightness, "brightness"])
    kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])

    cond do
      power in [:off, "off"] ->
        {"turn_off", %{"entity_id" => group.source_id}}

      power in [:on, "on"] or not is_nil(brightness) or not is_nil(kelvin) ->
        payload =
          %{"entity_id" => group.source_id}
          |> maybe_put("brightness", brightness && percent_to_brightness(brightness))

        payload =
          case kelvin do
            nil ->
              payload

            value ->
              if group.extended_kelvin_range && value < 2700 do
                {x, y} = extended_xy(value)
                Map.put(payload, "xy_color", [x, y])
              else
                kelvin = Kelvin.map_for_control(group, value)
                Map.put(payload, "color_temp_kelvin", round(kelvin))
              end
          end

        {"turn_on", payload}

      true ->
        :ignore
    end
  end

  defp action_payload({:brightness, level}, group) do
    {"turn_on", %{"entity_id" => group.source_id, "brightness" => percent_to_brightness(level)}}
  end

  defp action_payload({:color_temp, kelvin}, group) do
    if group.extended_kelvin_range && kelvin < 2700 do
      {x, y} = extended_xy(kelvin)
      {"turn_on", %{"entity_id" => group.source_id, "xy_color" => [x, y]}}
    else
      kelvin = Kelvin.map_for_control(group, kelvin)
      {"turn_on", %{"entity_id" => group.source_id, "color_temp_kelvin" => round(kelvin)}}
    end
  end

  defp action_payload({:color, {h, s}}, group) do
    {"turn_on", %{"entity_id" => group.source_id, "hs_color" => [round(h), round(s)]}}
  end

  defp action_payload(_action, _group), do: :ignore

  defp value_or_nil(desired, keys) do
    Enum.find_value(keys, fn key -> Map.get(desired, key) end)
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp percent_to_brightness(level) do
    level
    |> Util.clamp(1, 100)
    |> then(fn pct -> round(pct / 100 * 255) end)
  end

  defp extended_xy(kelvin) do
    k_fake = kelvin |> min(2700) |> max(2000)
    t_base = (k_fake - 2000) / 700
    t = min(1.0, t_base + 0.25 * (1.0 - t_base))
    s = 4.0 * t * (1.0 - t)
    x_core = 0.522 + (0.459 - 0.522) * t
    y_core = 0.405 + (0.41 - 0.405) * t
    x = x_core
    y = y_core + 0.03 * s
    {x, y}
  end
end
