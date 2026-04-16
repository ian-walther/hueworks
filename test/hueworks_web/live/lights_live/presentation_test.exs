defmodule HueworksWeb.LightsLive.PresentationTest do
  use ExUnit.Case, async: true

  alias HueworksWeb.LightsLive.Presentation

  test "manual_adjustment_locked? reflects whether a room has an active scene" do
    assert Presentation.manual_adjustment_locked?(%{1 => 10}, 1)
    refute Presentation.manual_adjustment_locked?(%{1 => 10}, 2)
    refute Presentation.manual_adjustment_locked?(nil, 1)
  end

  test "color preview falls back sanely when xy state is missing" do
    preview = Presentation.color_preview(%{}, 1)

    assert preview == %{hue: 0, saturation: 100, brightness: 100}
    assert Presentation.color_preview_label(%{}, 1) == "Color: 0°, 100% saturation, 100% brightness"
    assert Presentation.color_preview_style(%{}, 1) =~ "background-color: rgb("
    assert Presentation.color_saturation_scale_style(%{}, 1) =~ "linear-gradient"
  end

  test "state_value returns the keyed value or fallback" do
    state_map = %{1 => %{power: :on, brightness: 42}}

    assert Presentation.state_value(state_map, 1, :brightness, 100) == 42
    assert Presentation.state_value(state_map, 2, :brightness, 100) == 100
  end
end
