defmodule Hueworks.BridgeOnboarding.HomeAssistantTest do
  use ExUnit.Case, async: true

  import MdnsLite.DNS

  alias Hueworks.BridgeOnboarding.HomeAssistant
  alias Hueworks.BridgeOnboarding.HomeAssistant.Device
  alias Hueworks.BridgeOnboarding.HomeAssistant.Mdns

  test "mDNS discovery extracts the official instance identity and endpoint" do
    instance = ~c"My Home._home-assistant._tcp.local"
    target = ~c"1234567890abcdef.local"

    response = %{
      answer: [
        dns_rr(
          domain: ~c"_home-assistant._tcp.local",
          type: :ptr,
          class: :in,
          data: instance
        )
      ],
      additional: [
        dns_rr(
          domain: instance,
          type: :srv,
          class: :in,
          data: {0, 0, 8123, target}
        ),
        dns_rr(
          domain: instance,
          type: :txt,
          class: :in,
          data: [~c"location_name=Walther Home", ~c"uuid=1234567890abcdef"]
        ),
        dns_rr(
          domain: target,
          type: :a,
          class: :in,
          data: {192, 168, 1, 41}
        )
      ]
    }

    assert [
             %Device{
               id: "1234567890abcdef",
               host: "192.168.1.41",
               port: 8123,
               name: "Walther Home"
             }
           ] = Mdns.parse(response)
  end

  test "discovery returns actionable fallback guidance when mDNS finds nothing" do
    assert {:error, message} = HomeAssistant.discover(local: __MODULE__.EmptyDiscovery)
    assert message =~ "No Home Assistant instances were discovered"
    assert message =~ "manual"
  end

  defmodule EmptyDiscovery do
    def discover, do: {:ok, []}
  end
end
