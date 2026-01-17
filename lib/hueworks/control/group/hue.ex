defmodule Hueworks.Control.Group.Hue do
  @moduledoc false

  alias Hueworks.Bridges.Bridge
  alias Hueworks.Repo

  def handle(group, action) do
    with {:ok, host, api_key} <- bridge_credentials(group),
         payload <- action_payload(action),
         {:ok, _resp} <- request(host, api_key, "/groups/#{group.source_id}/action", payload) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  defp bridge_credentials(group) do
    host = group.metadata["bridge_host"]

    case Repo.get_by(Bridge, type: :hue, host: host) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        api_key = bridge.credentials["api_key"]

        if is_binary(api_key) and api_key != "" do
          {:ok, host, api_key}
        else
          {:error, :missing_api_key}
        end
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

  defp request(host, api_key, path, payload) do
    url = "http://#{host}/api/#{api_key}#{path}"
    body = Jason.encode!(payload)

    case HTTPoison.put(url, body, [{"Content-Type", "application/json"}], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> {:ok, :ok}
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, {:http_error, status_code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end

  defp percent_to_bri(level) do
    level
    |> clamp(1, 100)
    |> then(fn pct -> round(pct / 100 * 254) end)
  end

  defp kelvin_to_mired(kelvin) do
    kelvin
    |> clamp(1000, 6500)
    |> then(fn k -> round(1_000_000 / k) end)
  end

  defp hue_to_hue(hue) do
    hue
    |> clamp(0, 360)
    |> then(fn h -> round(h / 360 * 65_535) end)
  end

  defp sat_to_sat(sat) do
    sat
    |> clamp(0, 100)
    |> then(fn s -> round(s / 100 * 254) end)
  end

  defp clamp(value, min, max) when is_number(value) do
    value |> max(min) |> min(max)
  end
end
