defmodule Hueworks.BridgeOnboarding.MdnsTest do
  use ExUnit.Case, async: true

  import MdnsLite.DNS

  alias Hueworks.BridgeOnboarding.Mdns

  test "extracts normalized service instances without integration-specific construction" do
    service = ~c"_example._tcp.local"
    instance = ~c"Example Device._example._tcp.local"
    target = ~c"example-device.local"

    response = %{
      answer: [
        dns_rr(class: :in, type: :ptr, domain: service, data: instance)
      ],
      additional: [
        dns_rr(
          class: :in,
          type: :srv,
          domain: instance,
          data: {0, 0, 1234, target}
        ),
        dns_rr(
          class: :in,
          type: :txt,
          domain: instance,
          data: [~c"ID=stable-id", ~c"Name=Example Device"]
        ),
        dns_rr(class: :in, type: :a, domain: target, data: {192, 168, 1, 20})
      ]
    }

    assert [
             %{
               instance: "example device._example._tcp.local",
               target: "example-device.local",
               port: 1234,
               txt: %{"id" => "stable-id", "name" => "Example Device"},
               host: "192.168.1.20"
             }
           ] = Mdns.instances(response, service)
  end

  test "returns no instances for malformed or unrelated responses" do
    assert Mdns.instances(%{}, ~c"_example._tcp.local") == []
    assert Mdns.instances(%{answer: [], additional: []}, ~c"_example._tcp.local") == []
  end
end
