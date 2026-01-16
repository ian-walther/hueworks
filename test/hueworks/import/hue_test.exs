defmodule Hueworks.Import.HueTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Hue

  test "normalizes hue lights using map keys" do
    export = %{
      "bridges" => [
        %{
          "name" => "Bridge A",
          "host" => "10.0.0.2",
          "lights" => %{
            "8" => %{
              "name" => "Lamp",
              "uniqueid" => "00:11:22:33:44:55:66:77-0b",
              "mac" => "00:11:22:33:44:55:66:77"
            }
          }
        }
      ]
    }

    %{bridges: [%{bridge: bridge, lights: [light]}]} = Hue.normalize(export)

    assert bridge.type == :hue
    assert bridge.host == "10.0.0.2"
    assert light.source == :hue
    assert light.source_id == "8"
    assert light.metadata["mac"] == "00:11:22:33:44:55:66:77"
  end
end
