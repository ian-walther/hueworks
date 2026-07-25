defmodule Hueworks.ConnectionTest.HomeAssistant do
  @moduledoc false

  alias Hueworks.ConnectionTest.Message
  alias Hueworks.HomeAssistant.Host

  def test(host, token) do
    url = Host.http_url(host, "/api/config")
    headers = [{"Authorization", "Bearer #{token}"}]

    case HTTPoison.get(url, headers, recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"location_name" => name}} when is_binary(name) and name != "" -> {:ok, name}
          _ -> :ok
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, Message.http(:ha, host, status, body)}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Message.transport(:ha, host, reason)}
    end
  end
end
