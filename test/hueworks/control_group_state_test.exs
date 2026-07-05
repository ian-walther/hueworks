defmodule Hueworks.Control.GroupStateTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.GroupState

  test "derive_from_states prefers complete kelvin over stale xy values" do
    states = [
      %{power: :on, brightness: 37, kelvin: 2000, x: 0.5062, y: 0.4288},
      %{power: :on, brightness: 37, kelvin: 2000, x: 0.5063, y: 0.4287}
    ]

    assert GroupState.derive_from_states(states, 2) == %{
             power: :on,
             brightness: 37,
             kelvin: 2000
           }
  end

  test "derive_from_states derives xy when members have no complete kelvin state" do
    states = [
      %{power: :on, brightness: 60, x: 0.4112, y: 0.321},
      %{power: :on, brightness: 60, x: 0.4113, y: 0.3211}
    ]

    assert GroupState.derive_from_states(states, 2) == %{
             power: :on,
             brightness: 60,
             x: 0.4113,
             y: 0.3211
           }
  end
end
