defmodule Hueworks.ControlZ2MTopologyTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.Z2MTopology

  describe "entity_from_topic/2" do
    test "extracts device and group topics under the configured base topic" do
      assert Z2MTopology.entity_from_topic(["zigbee2mqtt", "Kitchen Strip"], ["zigbee2mqtt"]) ==
               "Kitchen Strip"

      assert Z2MTopology.entity_from_topic(
               ["zigbee2mqtt", "nested", "device", "state"],
               ["zigbee2mqtt"]
             ) == "nested/device"
    end

    test "ignores bridge and command topics" do
      base = ["zigbee2mqtt"]

      assert Z2MTopology.entity_from_topic(["zigbee2mqtt"], base) == nil
      assert Z2MTopology.entity_from_topic(["zigbee2mqtt", "bridge", "info"], base) == nil
      assert Z2MTopology.entity_from_topic(["zigbee2mqtt", "Kitchen Strip", "set"], base) == nil
      assert Z2MTopology.entity_from_topic(["zigbee2mqtt", "Kitchen Strip", "get"], base) == nil

      assert Z2MTopology.entity_from_topic(
               ["zigbee2mqtt", "Kitchen Strip", "availability"],
               base
             ) == nil
    end

    test "ignores topics outside the configured base topic" do
      assert Z2MTopology.entity_from_topic(["other", "Kitchen Strip"], ["zigbee2mqtt"]) == nil
    end
  end
end
