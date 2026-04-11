defmodule Hueworks.Control.StateTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State

  test "putting xy state clears stale kelvin" do
    _ = State.put(:light, 10_001, %{power: :on, brightness: 55, kelvin: 3200})
    _ = State.put(:light, 10_001, %{x: 0.2211, y: 0.3322})

    state = State.get(:light, 10_001)

    assert state[:power] == :on
    assert state[:brightness] == 55
    assert state[:x] == 0.2211
    assert state[:y] == 0.3322
    refute Map.has_key?(state, :kelvin)
  end

  test "putting kelvin state clears stale xy" do
    _ = State.put(:light, 10_002, %{power: :on, brightness: 60, x: 0.2, y: 0.3})
    _ = State.put(:light, 10_002, %{kelvin: 3100})

    state = State.get(:light, 10_002)

    assert state[:power] == :on
    assert state[:brightness] == 60
    assert state[:kelvin] == 3100
    refute Map.has_key?(state, :x)
    refute Map.has_key?(state, :y)
  end
end
