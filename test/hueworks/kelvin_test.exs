defmodule Hueworks.KelvinTest do
  use ExUnit.Case, async: true

  alias Hueworks.Kelvin

  test "maps kelvin values between actual and reported ranges" do
    entity = %{
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6500
    }

    assert Kelvin.map_for_control(entity, 2700) == 2000
    assert Kelvin.map_for_control(entity, 6500) == 6500
    assert Kelvin.map_for_control(entity, 4600) == 3915

    assert Kelvin.map_from_event(entity, 2000) == 2700
    assert Kelvin.map_from_event(entity, 6500) == 6500
    assert Kelvin.map_from_event(entity, 3915) == 4600
  end

  test "returns the original kelvin when ranges are missing" do
    entity = %{reported_min_kelvin: 2000, reported_max_kelvin: 6500}

    assert Kelvin.map_for_control(entity, 3000) == 3000
    assert Kelvin.map_from_event(entity, 3000) == 3000
  end

  test "derive_range extends to 2000K when enabled" do
    entity = %{reported_min_kelvin: 2700, reported_max_kelvin: 6500}
    assert Kelvin.derive_range(entity) == {2700, 6500}

    extended = Map.put(entity, :extended_kelvin_range, true)
    assert Kelvin.derive_range(extended) == {2000, 6500}
  end

  test "mapping_supported includes HA and Z2M sources" do
    assert Kelvin.mapping_supported?(%{source: :ha})
    assert Kelvin.mapping_supported?(%{source: :z2m})
    refute Kelvin.mapping_supported?(%{source: :hue})
  end

  test "extended range uses the same mired-space remap as the HA template for normal whites" do
    entity = %{
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    assert Kelvin.map_for_control(entity, 2700) == 2000
    assert Kelvin.map_for_control(entity, 2880) == 2158
    assert Kelvin.map_for_control(entity, 3000) == 2265
    assert Kelvin.map_for_control(entity, 3900) == 3125

    assert Kelvin.map_from_event(entity, 2158) == 2880
    assert Kelvin.map_from_event(entity, 2265) == 3000
    assert Kelvin.map_from_event(entity, 3125) == 3900
  end
end
