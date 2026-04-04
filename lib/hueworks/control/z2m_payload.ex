defmodule Hueworks.Control.Z2MPayload do
  @moduledoc false

  alias Hueworks.Control.HomeAssistantPayload
  alias Hueworks.Control.Transition
  alias Hueworks.Kelvin
  alias Hueworks.Util

  def action_payload(action, entity, opts \\ %{})

  def action_payload(:on, _entity, opts), do: with_transition(%{"state" => "ON"}, opts)
  def action_payload(:off, _entity, opts), do: with_transition(%{"state" => "OFF"}, opts)

  def action_payload({:set_state, desired}, entity, opts) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")
    brightness = value_or_nil(desired, [:brightness, "brightness"])
    kelvin = value_or_nil(desired, [:kelvin, "kelvin", :temperature, "temperature"])
    x = normalized_xy(value_or_nil(desired, [:x, "x"]))
    y = normalized_xy(value_or_nil(desired, [:y, "y"]))

    cond do
      power in [:off, "off"] ->
        with_transition(%{"state" => "OFF"}, opts)

      power in [:on, "on"] or not is_nil(brightness) or not is_nil(kelvin) or
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

  def action_payload({:brightness, level}, _entity, opts) do
    with_transition(%{"state" => "ON", "brightness" => percent_to_brightness(level)}, opts)
  end

  def action_payload({:color_temp, kelvin}, entity, opts) do
    %{"state" => "ON"}
    |> maybe_put_color_temp(kelvin, entity)
    |> with_transition(opts)
  end

  def action_payload(_action, _entity, _opts), do: :ignore

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
      power in [:on, "on"] or not is_nil(brightness) or not is_nil(kelvin) or
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
      {x, y} = HomeAssistantPayload.extended_xy(kelvin)
      Map.put(payload, "color", %{"x" => x, "y" => y})
    else
      Map.put(payload, "color_temp", kelvin_to_mired(kelvin, entity))
    end
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

  defp extended_low_kelvin?(entity, kelvin) when is_number(kelvin) do
    extended =
      Map.get(entity, :extended_kelvin_range) || Map.get(entity, "extended_kelvin_range")

    extended == true and kelvin < 2700
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
