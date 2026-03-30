defmodule Hueworks.Control.Z2MPayloadTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.Z2MPayload

  test "set_state builds off payload" do
    assert Z2MPayload.action_payload({:set_state, %{power: :off, brightness: 30}}, %{}) == %{
             "state" => "OFF"
           }
  end

  test "set_state maps brightness and kelvin to z2m fields" do
    payload =
      Z2MPayload.action_payload(
        {:set_state, %{power: :on, brightness: 50, kelvin: 4000}},
        %{}
      )

    assert payload["state"] == "ON"
    assert payload["brightness"] == 127
    assert payload["color_temp"] == 250
  end

  test "set_state returns ignore for empty desired" do
    assert Z2MPayload.action_payload({:set_state, %{}}, %{}) == :ignore
  end

  test "brightness and color_temp actions include power on" do
    assert Z2MPayload.action_payload({:brightness, 100}, %{}) == %{
             "state" => "ON",
             "brightness" => 254
           }

    assert Z2MPayload.action_payload({:color_temp, 2000}, %{}) == %{
             "state" => "ON",
             "color_temp" => 500
           }
  end

  test "extended kelvin range uses color mode payload below 2700K" do
    entity = %{
      source: :z2m,
      extended_kelvin_range: true,
      actual_min_kelvin: 2200,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2200,
      reported_max_kelvin: 6500
    }

    payload = Z2MPayload.action_payload({:color_temp, 2000}, entity)

    assert payload["state"] == "ON"
    assert is_map(payload["color"])
    assert is_number(payload["color"]["x"])
    assert is_number(payload["color"]["y"])
    refute Map.has_key?(payload, "color_temp")
  end

  test "set_state uses color mode payload below 2700K when extended kelvin is enabled" do
    entity = %{
      source: :z2m,
      extended_kelvin_range: true,
      actual_min_kelvin: 2200,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2200,
      reported_max_kelvin: 6500
    }

    payload = Z2MPayload.action_payload({:set_state, %{power: :on, kelvin: 2000}}, entity)

    assert payload["state"] == "ON"
    assert is_map(payload["color"])
    refute Map.has_key?(payload, "color_temp")
  end

  test "z2m color_temp payload applies actual->reported mapping above extended range floor" do
    entity = %{
      source: :z2m,
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    payload = Z2MPayload.action_payload({:color_temp, 3000}, entity)

    assert payload["state"] == "ON"
    assert payload["color_temp"] == 442
  end

  test "set_state applies actual->reported mapping above extended range floor" do
    entity = %{
      source: :z2m,
      extended_kelvin_range: true,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    }

    payload = Z2MPayload.action_payload({:set_state, %{power: :on, kelvin: 3000}}, entity)

    assert payload["state"] == "ON"
    assert payload["color_temp"] == 442
  end
end
