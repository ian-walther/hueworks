defmodule Hueworks.BridgeOnboarding.Caseta.Mdns do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.Caseta.Device
  alias Hueworks.BridgeOnboarding.Mdns

  @service ~c"_lutron._tcp.local"

  def discover(opts \\ []) do
    case Mdns.query(@service, 3_000, opts) do
      {:ok, response} -> {:ok, parse(response)}
      {:error, reason} -> {:error, reason}
    end
  end

  def resolve(id, resolver \\ &resolve_hostname/1) when is_binary(id) do
    id = String.downcase(id)

    case resolver.("lutron-#{id}.local") do
      {:ok, ip} ->
        case Mdns.format_ip(ip) do
          nil -> {:error, :not_found}
          host -> {:ok, %Device{id: id, host: host, name: "Lutron #{id}"}}
        end

      _other ->
        {:error, :not_found}
    end
  end

  def parse(response, resolver \\ &resolve_hostname/1) do
    response
    |> Mdns.instances(@service)
    |> Enum.map(&device_for_instance(&1, resolver))
    |> Enum.reject(&is_nil/1)
  end

  defp device_for_instance(instance, resolver) do
    with id when is_binary(id) <- bridge_id(instance.target),
         host when is_binary(host) <-
           instance.host || resolve_target(resolver, instance.target) do
      %Device{id: id, host: host, name: "Lutron #{id}"}
    else
      _other -> nil
    end
  end

  defp bridge_id(target) do
    case Regex.run(~r/^lutron-([^.]+)(?:\.|$)/i, target, capture: :all_but_first) do
      [id] -> String.downcase(id)
      _other -> nil
    end
  end

  defp resolve_target(resolver, target) do
    case resolver.(target) do
      {:ok, ip} -> Mdns.format_ip(ip)
      _other -> nil
    end
  end

  defp resolve_hostname(hostname) do
    case :inet.getaddr(String.to_charlist(hostname), :inet) do
      {:ok, _ip} = result -> result
      _other -> MdnsLite.gethostbyname(hostname, 3_000)
    end
  end
end
