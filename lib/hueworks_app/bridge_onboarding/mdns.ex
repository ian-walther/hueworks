defmodule Hueworks.BridgeOnboarding.Mdns do
  @moduledoc false

  import MdnsLite.DNS

  alias Hueworks.BridgeOnboarding.MdnsTransport

  def query(service, timeout, opts \\ []) do
    query = dns_query(class: :in, type: :ptr, domain: service)
    transport = Keyword.get(opts, :transport, MdnsTransport)
    transport.query(query, timeout)
  end

  def instances(%{answer: answers, additional: additional}, service) do
    records = List.wrap(answers) ++ List.wrap(additional)

    records
    |> ptr_instances(service)
    |> Enum.map(&instance(&1, records))
    |> Enum.reject(&is_nil/1)
  end

  def instances(_response, _service), do: []

  def format_ip({_, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  def format_ip(<<a, b, c, d>>), do: format_ip({a, b, c, d})
  def format_ip(value) when is_binary(value), do: value
  def format_ip(_value), do: nil

  def normalize_domain(value) do
    value
    |> to_string()
    |> String.trim_trailing(".")
    |> String.downcase()
  end

  defp ptr_instances(records, service) do
    records
    |> Enum.filter(fn record ->
      dns_rr(record, :type) == :ptr and
        normalize_domain(dns_rr(record, :domain)) == normalize_domain(service)
    end)
    |> Enum.map(&normalize_domain(dns_rr(&1, :data)))
    |> Enum.uniq()
  end

  defp instance(instance, records) do
    with %{data: {_priority, _weight, port, target}} <-
           record_data(records, instance, :srv),
         true <- is_integer(port) do
      target = normalize_domain(target)

      %{
        instance: instance,
        target: target,
        port: port,
        txt: txt_properties(find_record(records, instance, :txt)),
        host: address_for_target(records, target)
      }
    else
      _other -> nil
    end
  end

  defp record_data(records, domain, type) do
    case find_record(records, domain, type) do
      nil -> nil
      record -> %{data: dns_rr(record, :data)}
    end
  end

  defp find_record(records, domain, type) do
    Enum.find(records, fn record ->
      dns_rr(record, :type) == type and
        normalize_domain(dns_rr(record, :domain)) == normalize_domain(domain)
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
end
