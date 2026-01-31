defmodule Hueworks.Import.IdentifiersTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Identifiers

  test "light_external_id prefers stable identifiers by source" do
    hue_light = %{
      source: :hue,
      source_id: "1",
      metadata: %{"uniqueid" => "hue-unique"},
      identifiers: %{"mac" => "aa:bb:cc"}
    }

    assert Identifiers.light_external_id(hue_light) == "hue-unique"

    ha_light = %{
      source: :ha,
      source_id: "light.kitchen",
      metadata: %{"entity_id" => "light.kitchen"}
    }

    assert Identifiers.light_external_id(ha_light) == "light.kitchen"

    caseta_light = %{
      source: :caseta,
      source_id: "10",
      metadata: %{"device_id" => "caseta-123"},
      identifiers: %{"serial" => "serial-1"}
    }

    assert Identifiers.light_external_id(caseta_light) == "caseta-123"
  end

  test "group_external_id falls back to source_id" do
    hue_group = %{
      source: :hue,
      source_id: "group-1",
      metadata: %{}
    }

    assert Identifiers.group_external_id(hue_group) == "group-1"
  end
end
