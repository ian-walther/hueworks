defmodule Hueworks.Control.HuePayloadTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.HuePayload

  test "set_state includes transitiontime when configured" do
    payload =
      HuePayload.action_payload(
        {:set_state, %{power: :on, brightness: 50, kelvin: 4000}},
        %{transition_ms: 850}
      )

    assert payload["on"] == true
    assert payload["bri"] == 127
    assert payload["ct"] == 250
    assert payload["transitiontime"] == 9
  end

  test "off payload includes transitiontime when configured" do
    assert HuePayload.action_payload(:off, %{transition_ms: 500}) == %{
             "on" => false,
             "transitiontime" => 5
           }
  end
end
