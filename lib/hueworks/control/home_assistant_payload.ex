defmodule Hueworks.Control.HomeAssistantPayload do
  @moduledoc false

  alias Hueworks.Kelvin
  alias Hueworks.Util

  def action_payload(:on, entity), do: {"turn_on", %{"entity_id" => entity.source_id}}
  def action_payload(:off, entity), do: {"turn_off", %{"entity_id" => entity.source_id}}

  def action_payload({:set_state, desired}, entity) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")
    brightness = value_or_nil(desired, [:brightness, "brightness"])
    kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])

    cond do
      power in [:off, "off"] ->
        {"turn_off", %{"entity_id" => entity.source_id}}

      power in [:on, "on"] or not is_nil(brightness) or not is_nil(kelvin) ->
        payload =
          %{"entity_id" => entity.source_id}
          |> maybe_put("brightness", brightness && percent_to_brightness(brightness))

        payload =
          case kelvin do
            nil ->
              payload

            value ->
              if entity.extended_kelvin_range && value < 2700 do
                {x, y} = extended_xy(value)
                Map.put(payload, "xy_color", [x, y])
              else
                kelvin = Kelvin.map_for_control(entity, value)
                Map.put(payload, "color_temp_kelvin", round(kelvin))
              end
          end

        {"turn_on", payload}

      true ->
        :ignore
    end
  end

  def action_payload({:brightness, level}, entity) do
    {"turn_on", %{"entity_id" => entity.source_id, "brightness" => percent_to_brightness(level)}}
  end

  def action_payload({:color_temp, kelvin}, entity) do
    if entity.extended_kelvin_range && kelvin < 2700 do
      {x, y} = extended_xy(kelvin)
      {"turn_on", %{"entity_id" => entity.source_id, "xy_color" => [x, y]}}
    else
      kelvin = Kelvin.map_for_control(entity, kelvin)
      {"turn_on", %{"entity_id" => entity.source_id, "color_temp_kelvin" => round(kelvin)}}
    end
  end

  def action_payload({:color, {hue, sat}}, entity) do
    {"turn_on", %{"entity_id" => entity.source_id, "hs_color" => [round(hue), round(sat)]}}
  end

  def action_payload(_action, _entity), do: :ignore

  def percent_to_brightness(level) do
    level
    |> Util.normalize_percent()
    |> then(fn pct -> round(pct / 100 * 255) end)
  end

  def extended_xy(kelvin) do
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

  defp value_or_nil(desired, keys) do
    Enum.find_value(keys, fn key -> Map.get(desired, key) end)
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
