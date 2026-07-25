defmodule Hueworks.BridgeOnboarding.CasetaTest do
  use ExUnit.Case, async: true

  import MdnsLite.DNS

  alias Hueworks.BridgeOnboarding.Caseta
  alias Hueworks.BridgeOnboarding.Caseta.Mdns

  test "parses Lutron mDNS advertisements into stable bridge identities and addresses" do
    service = ~c"_lutron._tcp.local"
    instance = ~c"Lutron-047a00fc._lutron._tcp.local"
    target = ~c"Lutron-047a00fc.local"

    response = %{
      answer: [
        dns_rr(class: :in, type: :ptr, domain: service, data: instance)
      ],
      additional: [
        dns_rr(
          class: :in,
          type: :srv,
          domain: instance,
          data: {0, 0, 8081, target}
        ),
        dns_rr(
          class: :in,
          type: :txt,
          domain: instance,
          data: [~c"SYSTYPE=SmartBridge"]
        ),
        dns_rr(class: :in, type: :a, domain: target, data: {192, 168, 1, 123})
      ]
    }

    assert [device] = Mdns.parse(response)
    assert device.id == "047a00fc"
    assert device.host == "192.168.1.123"
    assert device.name == "Lutron 047a00fc"
  end

  test "resolves the advertised hostname when the service response omits an address" do
    service = ~c"_lutron._tcp.local"
    instance = ~c"Lutron Status._lutron._tcp.local"
    target = ~c"Lutron-047a00fc.local"

    response = %{
      answer: [
        dns_rr(class: :in, type: :ptr, domain: service, data: instance)
      ],
      additional: [
        dns_rr(
          class: :in,
          type: :srv,
          domain: instance,
          data: {0, 0, 22, target}
        )
      ]
    }

    resolver = fn "lutron-047a00fc.local" -> {:ok, {192, 168, 1, 123}} end

    assert [device] = Mdns.parse(response, resolver)
    assert device.id == "047a00fc"
    assert device.host == "192.168.1.123"
  end

  test "resolves a Home Assistant bridge identity directly before broad discovery" do
    assert {:ok, [device]} =
             Caseta.discover(
               mdns: __MODULE__.IdentityMdns,
               external_id: "047A00FC"
             )

    assert device.id == "047a00fc"
    assert device.host == "192.168.1.123"
  end

  defmodule IdentityMdns do
    def resolve("047a00fc") do
      {:ok, %{id: "047a00fc", host: "192.168.1.123", name: "Lutron 047a00fc"}}
    end

    def discover, do: raise("broad discovery should not run for a resolvable bridge identity")
  end
end
