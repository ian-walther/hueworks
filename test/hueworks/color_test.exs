defmodule Hueworks.ColorTest do
  use ExUnit.Case, async: true

  alias Hueworks.Color

  test "xy_to_hs approximately round-trips hs_to_xy output across representative colors" do
    samples = [
      {0, 100},
      {45, 80},
      {120, 70},
      {210, 60},
      {300, 90}
    ]

    Enum.each(samples, fn {input_hue, input_saturation} ->
      {x, y} = Color.hs_to_xy(input_hue, input_saturation)
      {hue, saturation} = Color.xy_to_hs(x, y)

      assert x > 0.0 and x < 1.0
      assert y > 0.0 and y < 1.0
      assert circular_hue_distance(hue, input_hue) <= 5
      assert_in_delta saturation, input_saturation, 8
    end)
  end

  test "hsb_to_rgb coerces bounded numeric inputs and rejects invalid ones" do
    assert Color.hsb_to_rgb("210", "60", "75") == {77, 134, 191}
    assert Color.hsb_to_rgb(nil, 60, 75) == nil
    assert Color.hsb_to_rgb("blue", 60, 75) == nil
  end

  test "kelvin_to_xy returns chromaticity points for representative white temperatures" do
    Enum.each([2000, 2700, 4000, 6500], fn kelvin ->
      {x, y} = Color.kelvin_to_xy(kelvin)

      assert is_float(x)
      assert is_float(y)
      assert x >= 0.0 and x <= 1.0
      assert y >= 0.0 and y <= 1.0
    end)
  end

  test "hs_to_xy treats wrapped hues equivalently" do
    assert Color.hs_to_xy(0, 80) == Color.hs_to_xy(360, 80)
    assert Color.hs_to_xy(-30, 80) == Color.hs_to_xy(0, 80)
  end

  test "xy_to_hs rejects out-of-bounds coordinates" do
    assert Color.xy_to_hs(-0.1, 0.2) == nil
    assert Color.xy_to_hs(0.2, 1.1) == nil
    assert Color.xy_to_hs(0.0, 0.2) == nil
  end

  defp circular_hue_distance(left, right) do
    diff = abs(left - right)
    min(diff, 360 - diff)
  end
end
