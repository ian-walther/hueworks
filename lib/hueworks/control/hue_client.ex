defmodule Hueworks.Control.HueClient do
  @moduledoc false

  def request(host, api_key, path, payload) do
    url = "http://#{host}/api/#{api_key}#{path}"
    body = Jason.encode!(payload)

    case HTTPoison.put(url, body, [{"Content-Type", "application/json"}], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        {:ok, :ok}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, {:http_error, status_code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end
end
