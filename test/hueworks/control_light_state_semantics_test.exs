defmodule Hueworks.Control.LightStateSemanticsTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.LightStateSemantics

  test "normalize_keys canonicalizes known state keys and preserves unknown keys" do
    assert LightStateSemantics.normalize_keys(%{
             "power" => "ON",
             "brightness" => 47,
             "temperature" => 2700,
             "x" => 0.22,
             "y" => 0.33,
             "vendor_field" => "kept"
           }) == %{
             "vendor_field" => "kept",
             power: :on,
             brightness: 47,
             kelvin: 2700,
             x: 0.22,
             y: 0.33
           }
  end

  test "merge_state canonicalizes incoming state before harmonizing color and temperature" do
    state =
      %{"power" => "on", "brightness" => 50, "kelvin" => 3000}
      |> LightStateSemantics.merge_state(%{"x" => 0.2, "y" => 0.3})

    assert state == %{power: :on, brightness: 50, x: 0.2, y: 0.3}
  end
end
