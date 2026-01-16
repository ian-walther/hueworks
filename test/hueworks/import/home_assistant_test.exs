defmodule Hueworks.Import.HomeAssistantTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.HomeAssistant

  test "normalizes home assistant lights with macs and serials" do
    export = %{
      "host" => "192.168.1.5",
      "light_entities" => [
        %{
          "entity_id" => "light.test_light",
          "name" => "Test Light",
          "unique_id" => "abc",
          "platform" => "hue",
          "source" => "hue",
          "device_id" => "dev1",
          "device" => %{
            "id" => "dev1",
            "connections" => [["mac", "00:11:22:33:44:55"]],
            "identifiers" => [["lutron_caseta", 1234]]
          }
        }
      ]
    }

    %{bridge: bridge, lights: [light]} = HomeAssistant.normalize(export)

    assert bridge.type == :ha
    assert light.source_id == "light.test_light"
    assert light.metadata["macs"] == ["00:11:22:33:44:55"]
    assert light.metadata["lutron_serial"] == 1234
  end
end
