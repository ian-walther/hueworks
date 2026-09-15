defmodule Hueworks.Control.HueClient do
  @moduledoc false

  # Type 901 is the bridge's "internal error" (HTTP 503 semantics): it is busy or over its
  # command budget and the same command may well succeed shortly. Every other error type is
  # a refusal of the command as sent (unknown resource, invalid value, device is off, ...)
  # that retrying would only repeat. See docs/hue-command-pacing.md.
  @busy_error_type 901

  def request(host, api_key, path, payload) do
    url = "http://#{host}/api/#{api_key}#{path}"
    body = Jason.encode!(payload)

    case HTTPoison.put(url, body, [{"Content-Type", "application/json"}], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        interpret_body(body)

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, {:http_error, status_code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end

  @doc """
  Interprets a Hue v1 API response body. The bridge answers HTTP 200 even when it refuses
  a command; refusals are `error` objects inside the result list. A body containing any
  error is a failure: `{:error, {:hue_busy, errors}}` when the bridge reported an internal
  error and the command is worth retrying, `{:error, {:hue_rejected, errors}}` otherwise.
  """
  def interpret_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, results} when is_list(results) ->
        case Enum.flat_map(results, &error_entries/1) do
          [] -> {:ok, :ok}
          errors -> {:error, {classify(errors), errors}}
        end

      _other ->
        {:ok, :ok}
    end
  end

  defp error_entries(%{"error" => error}) when is_map(error), do: [error]
  defp error_entries(_result), do: []

  defp classify(errors) do
    if Enum.any?(errors, &(Map.get(&1, "type") == @busy_error_type)),
      do: :hue_busy,
      else: :hue_rejected
  end
end
