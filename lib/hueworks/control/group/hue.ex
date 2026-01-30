defmodule Hueworks.Control.Group.Hue do
  @moduledoc false

  alias Hueworks.Control.{HueBridge, HueClient}
  alias Hueworks.Util

  def handle(group, action) do
    with {:ok, host, api_key} <- HueBridge.credentials_for(group),
         payload <- action_payload(action),
         {:ok, _resp} <- HueClient.request(host, api_key, "/groups/#{group.source_id}/action", payload) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp action_payload(:on), do: %{"on" => true}
  defp action_payload(:off), do: %{"on" => false}

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