defmodule Hueworks.ConnectionTest.HomeAssistant do
  @moduledoc false

  def test(host, token) do
    url = "http://#{normalize_host(host)}/api/config"
    headers = [{"Authorization", "Bearer #{token}"}]

    case HTTPoison.get(url, headers, recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"location_name" => name}} when is_binary(name) and name != "" -> {:ok, name}
          _ -> :ok
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Home Assistant test failed: #{status} #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Home Assistant test failed: #{inspect(reason)}"}
    end
  end

  defp normalize_host(host) when is_binary(host) do
    if String.contains?(host, ":") do
      host
    else
      "#{host}:8123"
    end
  end

  defp normalize_host(_host), do: "127.0.0.1:8123"
end
