defmodule Hueworks.Control.HomeAssistantPayload do
  @moduledoc false

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
        {"turn_off", with_transition(%{"entity_id" => entity.source_id}, opts)}

      power == :on or not is_nil(brightness) or not is_nil(kelvin) or
          (not is_nil(x) and not is_nil(y)) ->
        payload =
          %{"entity_id" => entity.source_id}
          |> maybe_put("brightness", brightness && percent_to_brightness(brightness))

        payload =
          cond do
            not is_nil(x) and not is_nil(y) ->
              Map.put(payload, "xy_color", [x, y])

            is_nil(kelvin) ->
              payload

            Kelvin.extended_low_kelvin?(entity, kelvin) ->
              {x, y} = extended_xy(entity, kelvin)
              Map.put(payload, "xy_color", [x, y])

            true ->
              kelvin = Kelvin.map_for_control(entity, kelvin)
              Map.put(payload, "color_temp_kelvin", round(kelvin))
          end

        {"turn_on", with_transition(payload, opts)}

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
    |> Util.normalize_percent()
    |> then(fn pct -> round(pct / 100 * 255) end)
  end

  def extended_xy(kelvin), do: extended_xy(%{extended_kelvin_range: true}, kelvin)

  def extended_xy(entity, kelvin) do
    Kelvin.extended_xy(entity, kelvin)
  end

  defp with_transition(payload, opts) do
    case Transition.seconds(opts) do
      value when is_number(value) -> Map.put(payload, "transition", value)
      _ -> payload
    end
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
