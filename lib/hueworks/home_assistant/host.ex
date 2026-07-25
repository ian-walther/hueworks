defmodule Hueworks.HomeAssistant.Host do
  @moduledoc false

  @default_port 8123

  def validate(host) when is_binary(host) do
    with {:ok, uri} <- parse(host),
         true <- uri.scheme in ["http", "https"],
         true <- is_binary(uri.host) and uri.host != "",
         true <- uri.path in [nil, "", "/"],
         true <- is_nil(uri.query) and is_nil(uri.fragment) do
      {:ok, canonical_base_url(uri)}
    else
      _ -> {:error, :invalid_host}
    end
  end

  def validate(_host), do: {:error, :invalid_host}

  def base_url(host) do
    case validate(host) do
      {:ok, url} -> url
      {:error, :invalid_host} -> raise ArgumentError, "invalid Home Assistant host"
    end
  end

  def http_url(host, path), do: append_path(base_url(host), path)

  def websocket_url(host, path) do
    uri = host |> base_url() |> URI.parse()
    scheme = if uri.scheme == "https", do: "wss", else: "ws"

    uri
    |> Map.put(:scheme, scheme)
    |> URI.to_string()
    |> append_path(path)
  end

  def normalize(host) when is_binary(host) do
    case validate(host) do
      {:ok, url} -> URI.parse(url).authority
      {:error, :invalid_host} -> "127.0.0.1:#{@default_port}"
    end
  end

  def normalize(_host), do: "127.0.0.1:#{@default_port}"

  defp parse(host) do
    host = String.trim(host)

    cond do
      host == "" ->
        {:error, :invalid_host}

      String.contains?(host, "://") ->
        {:ok, URI.parse(host)}

      true ->
        uri = URI.parse("http://#{host}")
        {:ok, if(explicit_port?(host), do: uri, else: %{uri | port: @default_port})}
    end
  end

  defp explicit_port?(host), do: String.match?(host, ~r/:\d+$/)

  defp canonical_base_url(uri) do
    uri
    |> Map.put(:path, nil)
    |> Map.put(:query, nil)
    |> Map.put(:fragment, nil)
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  defp append_path(base, path) do
    "#{String.trim_trailing(base, "/")}/#{path |> to_string() |> String.trim_leading("/")}"
  end
end
