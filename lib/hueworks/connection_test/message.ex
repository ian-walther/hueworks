defmodule Hueworks.ConnectionTest.Message do
  @moduledoc false

  @detail_limit 160

  def transport(_type, host, :nxdomain) do
    "HueWorks could not resolve #{host}. Check the address and local DNS, then retry."
  end

  def transport(type, host, :econnrefused) do
    "HueWorks reached #{host}, but the #{label(type)} connection was refused. Check the bridge service and credentials, then retry."
  end

  def transport(type, host, reason) when reason in [:timeout, :etimedout] do
    "#{label(type)} at #{host} did not respond before the timeout. Check that it is running and reachable, then retry."
  end

  def transport(type, host, reason) do
    "#{label(type)} at #{host} could not be reached. Check the address and network, then retry. Details: #{detail(reason)}"
  end

  def http(:ha, _host, status, _body) when status in [401, 403] do
    "Home Assistant rejected the token. Authorize again or enter a valid token, then retry."
  end

  def http(:hue, _host, status, _body) when status in [401, 403] do
    "Hue rejected the API key. Pair again or enter a valid key, then retry."
  end

  def http(type, host, 404, _body) do
    "#{label(type)} at #{host} did not expose the expected API. Check the address and bridge type, then retry."
  end

  def http(type, host, status, body) do
    "#{label(type)} at #{host} returned HTTP #{status}. Details: #{detail(body)}"
  end

  def unexpected(type, host, reason) do
    "#{label(type)} connection testing stopped unexpectedly. Retry the test. Details: #{detail(reason)}"
    |> maybe_include_host(host)
  end

  defp maybe_include_host(message, host) when is_binary(host) and host != "",
    do: "#{message} Target: #{host}."

  defp maybe_include_host(message, _host), do: message

  defp label(:ha), do: "Home Assistant"
  defp label(:hue), do: "Hue"
  defp label(:caseta), do: "Caseta"
  defp label(:z2m), do: "Zigbee2MQTT"
  defp label(type), do: type |> to_string() |> String.capitalize()

  defp detail(value) do
    value
    |> inspect_value()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, @detail_limit)
  end

  defp inspect_value(value) when is_binary(value), do: value
  defp inspect_value(value), do: inspect(value)
end
