defmodule Hueworks.ScenesPowerPolicyTest do
  use ExUnit.Case, async: true

  alias Hueworks.Scenes.PowerPolicy

  describe "parse/1" do
    test "normalizes canonical values" do
      for policy <- PowerPolicy.values() do
        assert PowerPolicy.parse(policy) == policy
        assert PowerPolicy.parse(to_string(policy)) == policy
      end
    end

    test "normalizes legacy on/off shapes" do
      for value <- [nil, true, "true", 1, "1", :on, "on"] do
        assert PowerPolicy.parse(value) == :default_on
      end

      for value <- [false, "false", 0, "0", :off, "off"] do
        assert PowerPolicy.parse(value) == :default_off
      end
    end

    test "defaults unknown values to default on" do
      assert PowerPolicy.parse(:mixed) == :default_on
      assert PowerPolicy.parse("wat") == :default_on
    end
  end

  describe "resolve/2" do
    test "resolves fixed power policies" do
      assert PowerPolicy.resolve(:default_on, nil) == :on
      assert PowerPolicy.resolve(:default_off, nil) == :off
      assert PowerPolicy.resolve(:force_on, nil) == :on
      assert PowerPolicy.resolve(:force_off, nil) == :off
    end

    test "resolves follow presence from occupied flag" do
      assert PowerPolicy.resolve(:follow_presence, %{occupied: true}) == :on
      assert PowerPolicy.resolve(:follow_presence, %{occupied: false}) == :off
      assert PowerPolicy.resolve(:follow_presence, nil) == :off
    end
  end

  test "overridable?/1 matches manual override semantics" do
    assert PowerPolicy.overridable?(:default_on)
    assert PowerPolicy.overridable?(:default_off)
    assert PowerPolicy.overridable?(:follow_presence)
    refute PowerPolicy.overridable?(:force_on)
    refute PowerPolicy.overridable?(:force_off)
  end

  test "preserves_manual_latch?/1 only allows ambient latches for fixed defaults" do
    assert PowerPolicy.preserves_manual_latch?(:default_on)
    assert PowerPolicy.preserves_manual_latch?(:default_off)
    refute PowerPolicy.preserves_manual_latch?(:follow_presence)
    refute PowerPolicy.preserves_manual_latch?(:force_on)
    refute PowerPolicy.preserves_manual_latch?(:force_off)
  end

  test "cycle/1 preserves the existing quick-toggle order" do
    assert PowerPolicy.cycle(:default_on) == :default_off
    assert PowerPolicy.cycle(:default_off) == :force_on
    assert PowerPolicy.cycle(:force_on) == :force_off
    assert PowerPolicy.cycle(:force_off) == :default_on
    assert PowerPolicy.cycle(:follow_presence) == :default_on
    assert PowerPolicy.cycle(:mixed) == :default_on
  end

  test "label/1 owns display labels" do
    assert PowerPolicy.label(:default_on) == "Default On"
    assert PowerPolicy.label(:default_off) == "Default Off"
    assert PowerPolicy.label(:force_on) == "Force On"
    assert PowerPolicy.label(:force_off) == "Force Off"
    assert PowerPolicy.label(:follow_presence) == "Follow Presence"
    assert PowerPolicy.label(:mixed) == "..."
  end
end
