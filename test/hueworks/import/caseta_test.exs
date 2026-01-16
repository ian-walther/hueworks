defmodule Hueworks.Import.CasetaTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Caseta

  test "normalizes caseta lights" do
    export = %{
      "bridge_ip" => "192.168.1.10",
      "lights" => [
        %{
          "name" => "Kitchen",
          "zone_id" => "12",
          "device_id" => "4",
          "serial" => 123456
        }
      ]
    }

    %{bridge: bridge, lights: [light]} = Caseta.normalize(export)

    assert bridge.type == :caseta
    assert bridge.host == "192.168.1.10"
    assert light.source_id == "12"
    assert light.metadata["serial"] == 123456
  end
end
