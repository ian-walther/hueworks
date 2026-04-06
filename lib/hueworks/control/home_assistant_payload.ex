defmodule Hueworks.Control.HomeAssistantPayload do
  @moduledoc false

  alias Hueworks.Control.Transition
  alias Hueworks.Kelvin
  alias Hueworks.Util

  def action_payload(action, entity, opts \\ %{})

  def action_payload(:on, entity, opts),
    do: {"turn_on", with_transition(%{"entity_id" => entity.source_id}, opts)}

  def action_payload(:off, entity, opts),
    do: {"turn_off", with_transition(%{"entity_id" => entity.source_id}, opts)}

  def action_payload({:set_state, desired}, entity, opts) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")
    brightness = value_or_nil(desired, [:brightness, "brightness"])
    kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])
    x = normalized_xy(value_or_nil(desired, [:x, "x"]))
    y = normalized_xy(value_or_nil(desired, [:y, "y"]))

    cond do
      power in [:off, "off"] ->
        {"turn_off", with_transition(%{"entity_id" => entity.source_id}, opts)}

      power in [:on, "on"] or not is_nil(brightness) or not is_nil(kelvin) or
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

  def action_payload({:brightness, level}, entity, opts) do
    {"turn_on",
     with_transition(
       %{"entity_id" => entity.source_id, "brightness" => percent_to_brightness(level)},
       opts
     )}
  end

  def action_payload({:color_temp, kelvin}, entity, opts) do
    if Kelvin.extended_low_kelvin?(entity, kelvin) do
      {x, y} = extended_xy(entity, kelvin)
      {"turn_on", with_transition(%{"entity_id" => entity.source_id, "xy_color" => [x, y]}, opts)}
    else
      kelvin = Kelvin.map_for_control(entity, kelvin)

      {"turn_on",
       with_transition(
         %{"entity_id" => entity.source_id, "color_temp_kelvin" => round(kelvin)},
         opts
       )}
    end
  end

  def action_payload({:color, {hue, sat}}, entity, opts) do
    {"turn_on",
     with_transition(
       %{"entity_id" => entity.source_id, "hs_color" => [round(hue), round(sat)]},
       opts
     )}
  end

  def action_payload(_action, _entity, _opts), do: :ignore

  def percent_to_brightness(level) do
    level
    |> Util.normalize_percent()
    |> then(fn pct -> round(pct / 100 * 255) end)
  end

  def extended_xy(kelvin), do: extended_xy(%{extended_kelvin_range: true}, kelvin)

  def extended_xy(entity, kelvin) do
    Kelvin.extended_xy(entity, kelvin)
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

  defp with_transition(payload, opts) do
    case Transition.seconds(opts) do
      value when is_number(value) -> Map.put(payload, "transition", value)
      _ -> payload
    end
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
