defmodule Hueworks.Control.HomeAssistantClient do
  @moduledoc false

  def request(host, token, service, payload) do
    url = "http://#{host}/api/services/light/#{service}"
    body = Jason.encode!(payload)
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post(url, body, headers, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> {:ok, :ok}
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, {:http_error, status_code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end
end
