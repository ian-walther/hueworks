defmodule Hueworks.ConnectionTest.Z2M do
  @moduledoc false

  @default_port 1883

  alias Hueworks.Util

  def test(host, opts \\ %{}) do
    host = normalize_host(host)

    if host == "" do
      {:error, "Z2M test failed: host is required."}
    else
      port =
        opts
        |> fetch_opt("broker_port")
        |> normalize_port()

      case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], 5_000) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          {:ok, "Zigbee2MQTT"}

        {:error, reason} ->
          {:error, "Z2M test failed: #{inspect(reason)}"}
      end
    end
  end

  defp fetch_opt(map, "broker_port") when is_map(map) do
    Map.get(map, "broker_port") || Map.get(map, :broker_port)
  end

  defp fetch_opt(_map, _key), do: nil

  defp normalize_host(host) when is_binary(host), do: Util.normalize_host_input(host)
  defp normalize_host(_host), do: ""

  defp normalize_port(nil), do: @default_port

  defp normalize_port(value) do
    case Util.parse_optional_integer(value) do
      port when is_integer(port) and port > 0 and port <= 65_535 -> port
      _ -> @default_port
    end
  end
end
