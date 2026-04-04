defmodule Hueworks.Control.HomeAssistantPayloadTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.HomeAssistantPayload

  test "set_state includes transition seconds when configured" do
    entity = %{source_id: "light.kitchen", extended_kelvin_range: false}

    assert {"turn_on", payload} =
             HomeAssistantPayload.action_payload(
               {:set_state, %{power: :on, brightness: 40, kelvin: 3000}},
               entity,
               %{transition_ms: 1250}
             )

    assert payload["entity_id"] == "light.kitchen"
    assert payload["transition"] == 1.25
  end

  test "off payload includes transition seconds when configured" do
    entity = %{source_id: "light.kitchen", extended_kelvin_range: false}

    assert {"turn_off", payload} =
             HomeAssistantPayload.action_payload(:off, entity, %{transition_ms: 500})

    assert payload == %{"entity_id" => "light.kitchen", "transition" => 0.5}
  end

  test "set_state uses xy_color when desired state includes color" do
    entity = %{source_id: "light.kitchen", extended_kelvin_range: false}

    assert {"turn_on", payload} =
             HomeAssistantPayload.action_payload(
               {:set_state, %{power: :on, brightness: 60, x: 0.4112, y: 0.321}},
               entity,
               %{}
             )

    assert payload["entity_id"] == "light.kitchen"
    assert payload["brightness"] == 153
    assert payload["xy_color"] == [0.4112, 0.321]
    refute Map.has_key?(payload, "color_temp_kelvin")
  end
end
