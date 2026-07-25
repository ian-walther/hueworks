defmodule Hueworks.ConnectionTest.MessageTest do
  use ExUnit.Case, async: true

  alias Hueworks.ConnectionTest.Message

  test "translates common transport failures into actionable language" do
    assert Message.transport(:hue, "hue.local", :nxdomain) ==
             "HueWorks could not resolve hue.local. Check the address and local DNS, then retry."

    assert Message.transport(:caseta, "192.168.1.20", :econnrefused) ==
             "HueWorks reached 192.168.1.20, but the Caseta connection was refused. Check the bridge service and credentials, then retry."

    assert Message.transport(:ha, "ha.local:8123", :timeout) ==
             "Home Assistant at ha.local:8123 did not respond before the timeout. Check that it is running and reachable, then retry."
  end

  test "classifies rejected credentials and truncates response details to one line" do
    assert Message.http(:ha, "ha.local:8123", 401, "unauthorized") ==
             "Home Assistant rejected the token. Authorize again or enter a valid token, then retry."

    message =
      Message.http(
        :hue,
        "192.168.1.10",
        500,
        String.duplicate("bridge failure\n", 30)
      )

    assert message =~ "Hue at 192.168.1.10 returned HTTP 500."
    refute message =~ "\n"
    assert String.length(message) < 260
  end
end
