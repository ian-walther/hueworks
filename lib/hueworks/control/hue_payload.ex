defmodule Hueworks.Control.HuePayload do
  @moduledoc false

  alias Hueworks.Util

  def action_payload(:on), do: %{"on" => true}
  def action_payload(:off), do: %{"on" => false}

  def action_payload({:set_state, desired}) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")

    case power do
      :off ->
        %{"on" => false}

      "off" ->
        %{"on" => false}

      _ ->
        brightness = value_or_nil(desired, [:brightness, "brightness"])
        kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])
        needs_on = power in [:on, "on"] or not is_nil(brightness) or not is_nil(kelvin)

        payload = %{}
        payload = maybe_put(payload, "on", needs_on)

        payload =
          case brightness do
            nil -> payload
            level -> maybe_put(payload, "bri", percent_to_bri(level))
          end

        payload =
          case kelvin do
            nil -> payload
            value -> maybe_put(payload, "ct", kelvin_to_mired(value))
          end

        payload
    end
  end

  def action_payload({:brightness, level}) do
    %{"on" => true, "bri" => percent_to_bri(level)}
  end

  def action_payload({:color_temp, kelvin}) do
    %{"on" => true, "ct" => kelvin_to_mired(kelvin)}
  end

  def action_payload({:color, {hue, sat}}) do
    %{"on" => true, "hue" => hue_to_hue(hue), "sat" => sat_to_sat(sat)}
  end

  def action_payload(_action), do: %{}

  def percent_to_bri(level) do
    level
    |> Util.normalize_percent()
    |> then(fn pct -> round(pct / 100 * 254) end)
  end

  def kelvin_to_mired(kelvin) do
    kelvin
    |> Util.normalize_kelvin_value()
    |> then(fn k -> round(1_000_000 / k) end)
  end

  def hue_to_hue(hue) do
    hue
    |> Util.normalize_hue_degrees()
    |> then(fn h -> round(h / 360 * 65_535) end)
  end

  def sat_to_sat(sat) do
    sat
    |> Util.normalize_saturation()
    |> then(fn s -> round(s / 100 * 254) end)
  end

  defp value_or_nil(desired, keys) do
    Enum.find_value(keys, fn key -> Map.get(desired, key) end)
  end

  defp maybe_put(payload, _key, false), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
