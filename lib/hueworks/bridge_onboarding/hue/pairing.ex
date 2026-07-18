defmodule Hueworks.BridgeOnboarding.Hue.Pairing do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.Hue.Device

  @http_options [recv_timeout: 5_000, timeout: 5_000]

  def pair(host, expected_external_id, opts \\ [])

  def pair(host, expected_external_id, opts) when is_binary(host) do
    http = Keyword.get(opts, :http, HTTPoison)
    host = normalize_host(host)

    with {:ok, api_key} <- register(http, host),
         {:ok, config} <- validate(http, host, api_key),
         external_id <- Device.normalize_id(config["bridgeid"] || expected_external_id),
         :ok <- verify_identity(expected_external_id, external_id) do
      {:ok,
       %{
         api_key: api_key,
         name: normalize_name(config["name"]),
         external_id: external_id
       }}
    end
  end

  def pair(_host, _expected_external_id, _opts), do: {:error, "A bridge address is required."}

  defp register(http, host) do
    body =
      Jason.encode!(%{
        "devicetype" => device_type(),
        "generateclientkey" => true
      })

    case http.post(
           "http://#{host}/api",
           body,
           [{"content-type", "application/json"}],
           @http_options
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_registration(body)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        pairing_http_error(status)

      {:error, _reason} ->
        {:error, "HueWorks could not reach that Hue bridge. Check its address and retry."}
    end
  end

  defp parse_registration(body) do
    case Jason.decode(body) do
      {:ok, [%{"success" => %{"username" => api_key}} | _]} when is_binary(api_key) ->
        {:ok, api_key}

      {:ok, [%{"error" => %{"type" => 101}} | _]} ->
        {:error, "Press the link button on the Hue bridge, then retry pairing within 30 seconds."}

      {:ok, [%{"error" => %{"description" => description}} | _]}
      when is_binary(description) ->
        {:error, "Hue pairing was rejected: #{sanitize_description(description)}"}

      _ ->
        {:error, "The Hue bridge returned an unsupported pairing response."}
    end
  end

  defp validate(http, host, api_key) do
    case http.get("http://#{host}/api/#{api_key}/config", [], @http_options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_config(body)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        validation_http_error(status)

      {:error, _reason} ->
        {:error, "Hue pairing succeeded, but the new credential could not be validated."}
    end
  end

  defp parse_config(body) do
    case Jason.decode(body) do
      {:ok, config} when is_map(config) and not is_map_key(config, "error") -> {:ok, config}
      _ -> {:error, "Hue pairing succeeded, but the new credential was not accepted."}
    end
  end

  defp verify_identity(nil, _actual), do: :ok
  defp verify_identity("", _actual), do: :ok

  defp verify_identity(expected, actual) do
    if Device.normalize_id(expected) == actual do
      :ok
    else
      {:error,
       "The Hue bridge identity changed during pairing. Rediscover bridges and try again."}
    end
  end

  defp pairing_http_error(status), do: {:error, "Hue pairing failed with HTTP status #{status}."}

  defp validation_http_error(status),
    do: {:error, "Hue credential validation failed with HTTP status #{status}."}

  defp device_type do
    instance = Application.get_env(:hueworks, :instance_name, "hueworks")
    "hueworks##{instance}" |> String.slice(0, 40)
  end

  defp normalize_host(host) do
    host
    |> String.trim()
    |> String.replace(~r{^https?://}i, "")
    |> String.trim_trailing("/")
  end

  defp normalize_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "Hue Bridge"
      value -> value
    end
  end

  defp normalize_name(_name), do: "Hue Bridge"

  defp sanitize_description(description) do
    description
    |> String.replace(~r/[\r\n\t]+/, " ")
    |> String.slice(0, 160)
  end
end
