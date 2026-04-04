defmodule Hueworks.Control.DesiredStateTest do
  use Hueworks.DataCase, async: true

  alias Hueworks.Control.DesiredState

  test "applying xy desired state clears stale kelvin state" do
    DesiredState.put(:light, 1, %{power: :on, brightness: 80, kelvin: 3000})

    txn =
      DesiredState.begin(:scene)
      |> DesiredState.apply(:light, 1, %{power: :on, brightness: 75, x: 0.1854, y: 0.2234})

    {:ok, %{updated: updated}} = DesiredState.commit(txn)
    assert updated[{:light, 1}] == %{power: :on, brightness: 75, x: 0.1854, y: 0.2234}
    assert DesiredState.get(:light, 1) == %{power: :on, brightness: 75, x: 0.1854, y: 0.2234}
  end

  test "applying kelvin desired state clears stale xy state" do
    DesiredState.put(:light, 1, %{power: :on, brightness: 75, x: 0.1854, y: 0.2234})

    txn =
      DesiredState.begin(:scene)
      |> DesiredState.apply(:light, 1, %{power: :on, brightness: 60, kelvin: 3200})

    {:ok, %{updated: updated}} = DesiredState.commit(txn)

    assert updated[{:light, 1}] == %{power: :on, brightness: 60, kelvin: 3200}
    assert DesiredState.get(:light, 1) == %{power: :on, brightness: 60, kelvin: 3200}
  end

  test "power off clears brightness, kelvin, and xy state" do
    DesiredState.put(:light, 1, %{power: :on, brightness: 75, x: 0.1854, y: 0.2234})

    txn =
      DesiredState.begin(:scene)
      |> DesiredState.apply(:light, 1, %{power: :off})

    {:ok, %{updated: updated}} = DesiredState.commit(txn)

    assert updated[{:light, 1}] == %{power: :off}
    assert DesiredState.get(:light, 1) == %{power: :off}
  end
end
