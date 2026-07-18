defmodule Hueworks.ConnectionTest.Z2M do
  @moduledoc false

  @default_port 1883

  alias Hueworks.Control.Z2MConfig
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

      config = %{
        host: host,
        port: port,
        username: opts |> fetch_opt("username") |> Z2MConfig.normalize_optional(),
        password: opts |> fetch_opt("password") |> Z2MConfig.normalize_optional(),
        base_topic: opts |> fetch_opt("base_topic") |> Z2MConfig.normalize_base_topic()
      }

      case snapshot_module().fetch(config) do
        {:ok, %{devices: devices, groups: groups}} when is_list(devices) and is_list(groups) ->
          {:ok,
           "Zigbee2MQTT (#{count_label(devices, "device")}, #{count_label(groups, "group")})"}

        {:ok, _snapshot} ->
          {:error, "Z2M test failed: retained devices or groups payload has an unexpected shape."}

        {:error, reason} ->
          {:error, "Z2M test failed: #{format_reason(reason)}"}
      end
    end
  end

  defp fetch_opt(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
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

  defp count_label(items, noun) do
    count = length(items)
    "#{count} #{noun}#{if count == 1, do: "", else: "s"}"
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp snapshot_module do
    Application.get_env(:hueworks, :z2m_snapshot_module, Hueworks.Z2M.Snapshot)
  end
end
