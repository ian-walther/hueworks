defmodule Hueworks.Import.Fetch.CommonTest do
  use Hueworks.DataCase, async: true

  alias Hueworks.Import.Fetch.Common

  describe "load_enabled_bridges/1" do
    test "returns only enabled bridges of the requested type" do
      enabled_hue =
        insert_bridge!(%{
          type: :hue,
          name: "Hue Enabled",
          host: "hue-enabled.local",
          enabled: true,
          credentials: %{"api_key" => "abc"}
        })

      _disabled_hue =
        insert_bridge!(%{
          type: :hue,
          name: "Hue Disabled",
          host: "hue-disabled.local",
          enabled: false,
          credentials: %{"api_key" => "def"}
        })

      _enabled_ha =
        insert_bridge!(%{
          type: :ha,
          name: "HA Enabled",
          host: "ha-enabled.local",
          enabled: true,
          credentials: %{"token" => "token"}
        })

      assert [bridge] = Common.load_enabled_bridges(:hue)
      assert bridge.id == enabled_hue.id
    end
  end

  describe "load_enabled_bridge!/1" do
    test "returns the single enabled bridge for a type" do
      bridge =
        insert_bridge!(%{
          type: :ha,
          name: "Primary HA",
          host: "ha.local",
          enabled: true,
          credentials: %{"token" => "token"}
        })

      assert %{id: id} = Common.load_enabled_bridge!(:ha)
      assert id == bridge.id
    end

    test "raises when no enabled bridge exists" do
      assert_raise RuntimeError, ~r/No enabled hue bridge found/, fn ->
        Common.load_enabled_bridge!(:hue)
      end
    end

    test "raises when multiple enabled bridges exist" do
      insert_bridge!(%{
        type: :hue,
        name: "Hue One",
        host: "hue-1.local",
        enabled: true,
        credentials: %{"api_key" => "abc"}
      })

      insert_bridge!(%{
        type: :hue,
        name: "Hue Two",
        host: "hue-2.local",
        enabled: true,
        credentials: %{"api_key" => "def"}
      })

      assert_raise RuntimeError, ~r/Multiple enabled hue bridges found/, fn ->
        Common.load_enabled_bridge!(:hue)
      end
    end
  end

  describe "invalid_credential?/1" do
    test "treats nil, blanks, and CHANGE_ME as invalid" do
      assert Common.invalid_credential?(nil)
      assert Common.invalid_credential?("")
      assert Common.invalid_credential?("CHANGE_ME")
      refute Common.invalid_credential?("real-token")
    end
  end
end
