defmodule Hueworks.ConnectionTest.Hue do
  @moduledoc false

  alias Hueworks.ConnectionTest.Message

  def test(host, api_key, opts \\ []) do
    url = "http://#{host}/api/#{api_key}/config"
    http = Keyword.get(opts, :http, HTTPoison)

    case http.get(url, [], recv_timeout: 5_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"name" => name} = config} when is_binary(name) and name != "" ->
            {:ok,
             %{
               name: name,
               external_id: normalize_external_id(Map.get(config, "bridgeid"))
             }}

          _ ->
            :ok
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, Message.http(:hue, host, status, body)}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Message.transport(:hue, host, reason)}
    end
  end

  defp normalize_external_id(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> nil
      external_id -> external_id
    end
  end

  defp normalize_external_id(_value), do: nil
end
