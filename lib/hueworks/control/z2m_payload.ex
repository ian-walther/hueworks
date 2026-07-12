defmodule Hueworks.Control.Z2MPayload do
  @moduledoc false

  alias Hueworks.Control.HomeAssistantPayload
  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.Transition
  alias Hueworks.Kelvin
  alias Hueworks.Util

  def action_payload(action, entity, opts \\ %{})

  def action_payload({:set_state, desired}, entity, opts) when is_map(desired) do
    power = LightStateSemantics.power_value(desired)
    brightness = LightStateSemantics.brightness_value(desired)
    kelvin = LightStateSemantics.kelvin_value(desired)
    x = LightStateSemantics.x_value(desired)
    y = LightStateSemantics.y_value(desired)

    cond do
      power == :off ->
        with_transition(%{"state" => "OFF"}, opts)

      power == :on or not is_nil(brightness) or not is_nil(kelvin) or
          (not is_nil(x) and not is_nil(y)) ->
        %{}
        |> maybe_put_state(power, brightness, kelvin, x, y)
        |> maybe_put_brightness(brightness)
        |> maybe_put_xy_color(x, y)
        |> maybe_put_color_temp(kelvin, entity)
        |> with_transition(opts)

      true ->
        :ignore
    end
  end

  def action_payload(_action, _entity, _opts), do: :ignore

  def effective_transition_ms(opts) do
    case Transition.seconds(opts) do
      value when is_number(value) and value > 0 -> round(value * 1_000)
      _ -> 0
    end
  end

  def percent_to_brightness(level) do
    level
    |> Util.normalize_percent(0, 100)
    |> then(fn pct -> round(pct / 100 * 254) end)
  end

  def kelvin_to_mired(kelvin, entity) do
    kelvin
    |> then(&Kelvin.map_for_control(entity, &1))
    |> Util.normalize_kelvin_value()
    |> then(fn value -> round(1_000_000 / value) end)
  end

  defp maybe_put_state(payload, power, brightness, kelvin, x, y) do
    needs_on =
      power == :on or not is_nil(brightness) or not is_nil(kelvin) or
        (not is_nil(x) and not is_nil(y))

    if needs_on, do: Map.put(payload, "state", "ON"), else: payload
  end

  defp maybe_put_brightness(payload, nil), do: payload

  defp maybe_put_brightness(payload, level) do
    Map.put(payload, "brightness", percent_to_brightness(level))
  end

  defp maybe_put_xy_color(payload, nil, _y), do: payload
  defp maybe_put_xy_color(payload, _x, nil), do: payload

  defp maybe_put_xy_color(payload, x, y) do
    Map.put(payload, "color", %{"x" => x, "y" => y})
  end

  defp maybe_put_color_temp(payload, nil, _entity), do: payload

  defp maybe_put_color_temp(%{"color" => _} = payload, _kelvin, _entity), do: payload

  defp maybe_put_color_temp(payload, kelvin, entity) do
    if extended_low_kelvin?(entity, kelvin) do
      {x, y} = HomeAssistantPayload.extended_xy(entity, kelvin)
      Map.put(payload, "color", %{"x" => x, "y" => y})
    else
      Map.put(payload, "color_temp", kelvin_to_mired(kelvin, entity))
    end
  end

  defp extended_low_kelvin?(entity, kelvin) when is_number(kelvin) do
    Kelvin.extended_low_kelvin?(entity, kelvin)
  end

  defp extended_low_kelvin?(_entity, _kelvin), do: false

  defp with_transition(:ignore, _opts), do: :ignore

  defp with_transition(payload, opts) when is_map(payload) do
    case Transition.seconds(opts) do
      value when is_number(value) -> Map.put(payload, "transition", value)
      _ -> payload
    end
  end
end
