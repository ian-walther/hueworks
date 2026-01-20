defmodule Hueworks.ConnectionTest.Hue do
  @moduledoc false

  def test(host, api_key) do
    url = "http://#{host}/api/#{api_key}/config"

    case HTTPoison.get(url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"name" => name}} when is_binary(name) and name != "" -> {:ok, name}
          _ -> :ok
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "Hue test failed: #{status} #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Hue test failed: #{inspect(reason)}"}
    end
  end
end
