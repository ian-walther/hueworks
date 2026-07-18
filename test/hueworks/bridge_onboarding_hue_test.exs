defmodule Hueworks.BridgeOnboarding.HueTest do
  use ExUnit.Case, async: false

  alias Hueworks.BridgeOnboarding.Hue
  alias Hueworks.BridgeOnboarding.Hue.Device
  alias Hueworks.BridgeOnboarding.Hue.{Mdns, VendorDiscovery}

  import MdnsLite.DNS

  test "discovery combines local and vendor results by stable bridge identity" do
    assert {:ok, devices} =
             Hue.discover(
               local: __MODULE__.LocalDiscovery,
               fallback: __MODULE__.CloudDiscovery
             )

    assert [first, second] = devices

    assert %Device{
             id: "001788fffe111111",
             host: "192.168.1.10",
             name: "Office Hue",
             sources: [:mdns, :vendor]
           } = first

    assert %Device{
             id: "001788fffe222222",
             host: "192.168.1.11",
             sources: [:vendor]
           } = second
  end

  test "discovery still returns local results when the vendor fallback is unavailable" do
    assert {:ok, [%Device{id: "001788fffe111111", sources: [:mdns]}]} =
             Hue.discover(
               local: __MODULE__.LocalDiscovery,
               fallback: __MODULE__.FailedDiscovery
             )
  end

  test "discovery reports a useful error when every bounded mechanism fails" do
    assert {:error, message} =
             Hue.discover(
               local: __MODULE__.FailedDiscovery,
               fallback: __MODULE__.FailedDiscovery
             )

    assert message =~ "No Hue bridges were discovered"
  end

  test "vendor discovery keeps the API host independent from its advertised TLS port" do
    body =
      Jason.encode!([
        %{"id" => "001788FFFE111111", "internalipaddress" => "192.168.1.10", "port" => 443}
      ])

    assert {:ok, [%Device{id: "001788FFFE111111", host: "192.168.1.10"}]} =
             VendorDiscovery.parse(body)
  end

  test "mDNS discovery extracts stable identity, host, and display metadata" do
    instance = ~c"Office Hue._hue._tcp.local"
    target = ~c"001788fffe111111.local"

    response = %{
      answer: [
        dns_rr(
          domain: ~c"_hue._tcp.local",
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
          data: {0, 0, 443, target}
        ),
        dns_rr(
          domain: instance,
          type: :txt,
          class: :in,
          data: [~c"bridgeid=001788FFFE111111", ~c"name=Office Hue"]
        ),
        dns_rr(
          domain: target,
          type: :a,
          class: :in,
          data: {192, 168, 1, 10}
        )
      ]
    }

    assert [
             %Device{
               id: "001788FFFE111111",
               host: "192.168.1.10",
               name: "Office Hue",
               sources: [:mdns]
             }
           ] = Mdns.parse(response)
  end

  test "pairing registers an application and validates the resulting credential" do
    assert {:ok, result} =
             Hue.pair("192.168.1.10", "001788FFFE111111", http: __MODULE__.PairingHttp)

    assert result.api_key == "generated-key"
    assert result.name == "Office Hue"
    assert result.external_id == "001788fffe111111"
  end

  test "pairing explains that the physical link button has not been pressed" do
    assert {:error, message} =
             Hue.pair("192.168.1.10", nil, http: __MODULE__.LinkButtonHttp)

    assert message =~ "Press the link button"
    refute message =~ "generated-key"
  end

  test "pairing rejects a bridge whose validated identity differs from discovery" do
    assert {:error, message} =
             Hue.pair("192.168.1.10", "different-bridge", http: __MODULE__.PairingHttp)

    assert message =~ "identity changed"
  end
end

defmodule Hueworks.BridgeOnboarding.HueTest.LocalDiscovery do
  alias Hueworks.BridgeOnboarding.Hue.Device

  def discover do
    {:ok,
     [
       %Device{
         id: "001788FFFE111111",
         host: "192.168.1.10",
         name: "Office Hue",
         sources: [:mdns]
       }
     ]}
  end
end

defmodule Hueworks.BridgeOnboarding.HueTest.CloudDiscovery do
  alias Hueworks.BridgeOnboarding.Hue.Device

  def discover do
    {:ok,
     [
       %Device{
         id: "001788fffe111111",
         host: "192.168.1.10",
         sources: [:vendor]
       },
       %Device{
         id: "001788fffe222222",
         host: "192.168.1.11",
         sources: [:vendor]
       }
     ]}
  end
end

defmodule Hueworks.BridgeOnboarding.HueTest.FailedDiscovery do
  def discover, do: {:error, "network unavailable"}
end

defmodule Hueworks.BridgeOnboarding.HueTest.PairingHttp do
  def post("http://192.168.1.10/api", body, headers, _opts) do
    assert_json_request(body, headers)

    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body: Jason.encode!([%{"success" => %{"username" => "generated-key"}}])
     }}
  end

  def get("http://192.168.1.10/api/generated-key/config", [], _opts) do
    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body: Jason.encode!(%{"name" => "Office Hue", "bridgeid" => "001788FFFE111111"})
     }}
  end

  defp assert_json_request(body, headers) do
    payload = Jason.decode!(body)
    true = is_binary(payload["devicetype"])
    true = payload["generateclientkey"]
    true = {"content-type", "application/json"} in headers
  end
end

defmodule Hueworks.BridgeOnboarding.HueTest.LinkButtonHttp do
  def post(_url, _body, _headers, _opts) do
    {:ok,
     %HTTPoison.Response{
       status_code: 200,
       body:
         Jason.encode!([
           %{"error" => %{"type" => 101, "description" => "link button not pressed"}}
         ])
     }}
  end
end
