defmodule Hueworks.Control.HuePayload do
  @moduledoc false

  alias Hueworks.Control.Transition
  alias Hueworks.Util

  def action_payload(action, opts \\ %{})

  def action_payload(:on, opts), do: with_transition(%{"on" => true}, opts)
  def action_payload(:off, opts), do: with_transition(%{"on" => false}, opts)

  def action_payload({:set_state, desired}, opts) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")

    case power do
      :off ->
        with_transition(%{"on" => false}, opts)

      "off" ->
        with_transition(%{"on" => false}, opts)

      _ ->
        brightness = value_or_nil(desired, [:brightness, "brightness"])
        kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])
        x = normalized_xy(value_or_nil(desired, [:x, "x"]))
        y = normalized_xy(value_or_nil(desired, [:y, "y"]))

        needs_on =
          power in [:on, "on"] or not is_nil(brightness) or not is_nil(kelvin) or
            (not is_nil(x) and not is_nil(y))

        payload = %{}
        payload = maybe_put(payload, "on", needs_on)

        payload =
          case brightness do
            nil -> payload
            level -> maybe_put(payload, "bri", percent_to_bri(level))
          end

        payload =
          cond do
            not is_nil(x) and not is_nil(y) ->
              maybe_put(payload, "xy", [x, y])

            is_nil(kelvin) ->
              payload

            true ->
              maybe_put(payload, "ct", kelvin_to_mired(kelvin))
          end

        with_transition(payload, opts)
    end
  end

  def action_payload({:brightness, level}, opts) do
    with_transition(%{"on" => true, "bri" => percent_to_bri(level)}, opts)
  end

  def action_payload({:color_temp, kelvin}, opts) do
    with_transition(%{"on" => true, "ct" => kelvin_to_mired(kelvin)}, opts)
  end

  def action_payload({:color, {hue, sat}}, opts) do
    with_transition(%{"on" => true, "hue" => hue_to_hue(hue), "sat" => sat_to_sat(sat)}, opts)
  end

  def action_payload(_action, _opts), do: %{}

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
    Enum.reduce_while(keys, nil, fn key, _acc ->
      if Map.has_key?(desired, key) do
        {:halt, Map.get(desired, key)}
      else
        {:cont, nil}
      end
    end)
  end

  defp normalized_xy(value) do
    case Util.to_number(value) do
      nil -> nil
      number -> Float.round(number, 4)
    end
  end

  defp with_transition(payload, opts) when is_map(payload) do
    case Transition.hue_transitiontime(opts) do
      value when is_integer(value) -> Map.put(payload, "transitiontime", value)
      _ -> payload
    end
  end

  defp maybe_put(payload, _key, false), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
