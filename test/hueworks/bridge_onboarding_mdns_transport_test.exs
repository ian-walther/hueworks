defmodule Hueworks.BridgeOnboarding.MdnsTransportTest do
  use ExUnit.Case, async: true

  import MdnsLite.DNS

  alias Hueworks.BridgeOnboarding.MdnsTransport

  test "sends one unicast query and merges every response packet" do
    query = dns_query(class: :in, type: :ptr, domain: ~c"_home-assistant._tcp.local")
    instance = ~c"Home._home-assistant._tcp.local"
    target = ~c"home-assistant.local"

    Process.put(:mdns_packets, [
      packet(
        [dns_rr(domain: ~c"_home-assistant._tcp.local", type: :ptr, data: instance)],
        [dns_rr(domain: instance, type: :srv, data: {0, 0, 8123, target})]
      ),
      packet([], [dns_rr(domain: target, type: :a, data: {192, 168, 1, 41})])
    ])

    assert {:ok, response} =
             MdnsTransport.query(query, 100, backend: __MODULE__.Backend)

    assert length(response.answer) == 1
    assert length(response.additional) == 2
    assert Process.get(:mdns_send_count) == 1
    assert Process.get(:mdns_closed?) == true

    {:ok, sent_message} = Process.get(:mdns_payload) |> MdnsLite.DNS.decode()
    [sent_query] = dns_rec(sent_message, :qdlist)
    assert dns_query(sent_query, :unicast_response) == true
  end

  test "closes the socket and returns transport errors" do
    Process.put(:mdns_send_result, {:error, :network_down})
    query = dns_query(class: :in, type: :ptr, domain: ~c"_home-assistant._tcp.local")

    assert {:error, :network_down} =
             MdnsTransport.query(query, 100, backend: __MODULE__.Backend)

    assert Process.get(:mdns_closed?) == true
  end

  defp packet(answers, additional) do
    dns_rec(
      header: dns_header(id: 0, qr: true, aa: true),
      anlist: answers,
      arlist: additional
    )
    |> MdnsLite.DNS.encode()
  end

  defmodule Backend do
    def open do
      Process.put(:mdns_send_count, 0)
      Process.put(:mdns_closed?, false)
      {:ok, :socket}
    end

    def send(:socket, _address, _port, payload) do
      Process.put(:mdns_send_count, Process.get(:mdns_send_count, 0) + 1)
      Process.put(:mdns_payload, payload)
      Process.get(:mdns_send_result, :ok)
    end

    def recv(:socket, _timeout) do
      case Process.get(:mdns_packets, []) do
        [packet | remaining] ->
          Process.put(:mdns_packets, remaining)
          {:ok, {{192, 168, 1, 41}, 5_353, packet}}

        [] ->
          {:error, :timeout}
      end
    end

    def close(:socket) do
      Process.put(:mdns_closed?, true)
      :ok
    end
  end
end
