defmodule Hueworks.Control.Light.Hue do
  @moduledoc false

  alias Hueworks.Control.{HueBridge, HueClient}
  alias Hueworks.Util

  def handle(light, action) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(light),
         payload <- action_payload(action),
         {:ok, _resp} <-
           HueClient.request(host, api_key, "/lights/#{light.source_id}/state", payload) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp action_payload(:on), do: %{"on" => true}
  defp action_payload(:off), do: %{"on" => false}

  defp action_payload({:set_state, desired}) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")

    case power do
      :off ->
        %{"on" => false}

      "off" ->
        %{"on" => false}

      _ ->
        brightness = maybe_value(desired, [:brightness, "brightness"])
        kelvin = maybe_value(desired, [:kelvin, "kelvin", :temperature, "temperature"])
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

  defp action_payload({:brightness, level}) do
    %{"on" => true, "bri" => percent_to_bri(level)}
  end

  defp action_payload({:color_temp, kelvin}) do
    %{"on" => true, "ct" => kelvin_to_mired(kelvin)}
  end

  defp action_payload({:color, {h, s}}) do
    %{"on" => true, "hue" => hue_to_hue(h), "sat" => sat_to_sat(s)}
  end

  defp action_payload(_action), do: %{}

  defp maybe_value(desired, keys) do
    Enum.find_value(keys, fn key -> Map.get(desired, key) end)
  end

  defp maybe_put(payload, _key, false), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp percent_to_bri(level) do
    level
    |> Util.clamp(1, 100)
    |> then(fn pct -> round(pct / 100 * 254) end)
  end

  defp kelvin_to_mired(kelvin) do
    kelvin
    |> Util.clamp(1000, 6500)
    |> then(fn k -> round(1_000_000 / k) end)
  end

  defp hue_to_hue(hue) do
    hue
    |> Util.clamp(0, 360)
    |> then(fn h -> round(h / 360 * 65_535) end)
  end

  defp sat_to_sat(sat) do
    sat
    |> Util.clamp(0, 100)
    |> then(fn s -> round(s / 100 * 254) end)
  end
end
