defmodule Hueworks.ColorTest do
  use ExUnit.Case, async: true

  alias Hueworks.Color

  test "xy_to_hs approximately round-trips hs_to_xy output" do
    {x, y} = Color.hs_to_xy(210, 60)
    {hue, saturation} = Color.xy_to_hs(x, y)

    assert_in_delta hue, 210, 3
    assert_in_delta saturation, 60, 5
  end
end
