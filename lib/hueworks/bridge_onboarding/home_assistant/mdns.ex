defmodule Hueworks.BridgeOnboarding.HomeAssistant.Mdns do
  @moduledoc false

  import MdnsLite.DNS

  alias Hueworks.BridgeOnboarding.HomeAssistant.Device

  @service ~c"_home-assistant._tcp.local"

  def discover do
    query = dns_query(class: :in, type: :ptr, domain: @service)
    response = MdnsLite.query(query, 1_000)
    {:ok, parse(response)}
  end

  def parse(%{answer: answers, additional: additional}) do
    records = List.wrap(answers) ++ List.wrap(additional)

    records
    |> ptr_instances()
    |> Enum.map(&device_for_instance(&1, records))
    |> Enum.reject(&is_nil/1)
  end

  def parse(_response), do: []

  defp ptr_instances(records) do
    records
    |> Enum.filter(fn record ->
      dns_rr(record, :type) == :ptr and same_domain?(dns_rr(record, :domain), @service)
    end)
    |> Enum.map(&normalize_domain(dns_rr(&1, :data)))
    |> Enum.uniq()
  end

  defp device_for_instance(instance, records) do
    srv = find_record(records, instance, :srv)

    case srv && dns_rr(srv, :data) do
      {_priority, _weight, port, target} when is_integer(port) ->
        target = normalize_domain(target)
        txt = records |> find_record(instance, :txt) |> txt_properties()
        host = address_for_target(records, target) || target

        %Device{
          id: txt["uuid"] || String.replace_suffix(target, ".local", ""),
          host: host,
          port: port,
          name: txt["location_name"] || instance_name(instance)
        }
        |> Device.normalize()

      _other ->
        nil
    end
  end

  defp find_record(records, domain, type) do
    Enum.find(records, fn record ->
      dns_rr(record, :type) == type and same_domain?(dns_rr(record, :domain), domain)
    end)
  end

  defp address_for_target(records, target) do
    case find_record(records, target, :a) do
      nil -> nil
      record -> record |> dns_rr(:data) |> format_ip()
    end
  end

  defp txt_properties(nil), do: %{}

  defp txt_properties(record) do
    record
    |> dns_rr(:data)
    |> List.wrap()
    |> Enum.reduce(%{}, fn item, acc ->
      case String.split(to_string(item), "=", parts: 2) do
        [key, value] -> Map.put(acc, String.downcase(key), value)
        _other -> acc
      end
    end)
  end

  defp format_ip({_, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  defp format_ip(<<a, b, c, d>>), do: format_ip({a, b, c, d})
  defp format_ip(_value), do: nil

  defp same_domain?(left, right), do: normalize_domain(left) == normalize_domain(right)

  defp normalize_domain(value) do
    value
    |> to_string()
    |> String.trim_trailing(".")
    |> String.downcase()
  end

  defp instance_name(instance) do
    instance
    |> String.replace_suffix("._home-assistant._tcp.local", "")
    |> String.trim()
    |> case do
      "" -> nil
      name -> name
    end
  end
end
