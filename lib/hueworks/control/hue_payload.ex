defmodule Hueworks.Control.HuePayload do
  @moduledoc false

  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.Transition
  alias Hueworks.Util

  def action_payload(action, opts \\ %{})

  def action_payload({:set_state, desired}, opts) when is_map(desired) do
    power = LightStateSemantics.power_value(desired)

    case power do
      :off ->
        with_transition(%{"on" => false}, opts)

      _ ->
        brightness = LightStateSemantics.brightness_value(desired)
        kelvin = LightStateSemantics.kelvin_value(desired)
        x = LightStateSemantics.x_value(desired)
        y = LightStateSemantics.y_value(desired)

        needs_on =
          power == :on or not is_nil(brightness) or not is_nil(kelvin) or
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

  def action_payload(_action, _opts), do: %{}

  def effective_transition_ms(opts) do
    case Transition.hue_transitiontime(opts) do
      value when is_integer(value) and value > 0 -> value * 100
      _ -> 0
    end
  end

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

  defp with_transition(payload, opts) when is_map(payload) do
    case Transition.hue_transitiontime(opts) do
      value when is_integer(value) -> Map.put(payload, "transitiontime", value)
      _ -> payload
    end
  end

  defp maybe_put(payload, _key, false), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
