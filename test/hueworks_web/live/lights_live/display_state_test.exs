defmodule HueworksWeb.LightsLive.DisplayStateTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State
  alias HueworksWeb.LightsLive.DisplayState

  test "build_light_state supplies display defaults without fabricating physical observations" do
    light = %{
      id: 42,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 4000,
      extended_kelvin_range: false
    }

    assert DisplayState.build_light_state([light]) == %{
             42 => %{power: :off, brightness: 75, kelvin: 3000}
           }

    assert State.get(:light, 42) == nil
  end
end
