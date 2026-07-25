defmodule Hueworks.HomeAssistant.HostTest do
  use ExUnit.Case, async: true

  alias Hueworks.HomeAssistant.Host

  test "bare hosts use Home Assistant's default local port" do
    assert Host.base_url("ha.local") == "http://ha.local:8123"
    assert Host.http_url("ha.local", "/api/config") == "http://ha.local:8123/api/config"

    assert Host.websocket_url("ha.local", "/api/websocket") ==
             "ws://ha.local:8123/api/websocket"
  end

  test "explicit schemes and ports are preserved" do
    assert Host.base_url("https://ha.example.test") == "https://ha.example.test"

    assert Host.websocket_url("https://ha.example.test", "/api/websocket") ==
             "wss://ha.example.test/api/websocket"

    assert Host.http_url("http://ha.home:8124/", "/auth/token") ==
             "http://ha.home:8124/auth/token"
  end

  test "invalid Home Assistant addresses are rejected" do
    assert {:error, :invalid_host} = Host.validate("")
    assert {:error, :invalid_host} = Host.validate("ftp://ha.local")
    assert {:error, :invalid_host} = Host.validate("http://ha.local/subpath")
  end
end
