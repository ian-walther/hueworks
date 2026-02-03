defmodule Hueworks.DesiredStateTest do
  use ExUnit.Case, async: false

  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.State, as: PhysicalState

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      :ets.delete_all_objects(:hueworks_desired_state)
    end

    :ok
  end

  test "commit computes diffs against physical state and omits brightness/kelvin when off" do
    _ = PhysicalState.put(:light, 1, %{power: :on, brightness: 50, kelvin: 3200})

    txn =
      DesiredState.begin("scene-1")
      |> DesiredState.apply(:light, 1, %{power: :off, brightness: 10, kelvin: 4000})

    {:ok, diff, _updated} = DesiredState.commit(txn)

    assert diff[{:light, 1}] == %{power: :off}
    assert DesiredState.get(:light, 1) == %{power: :off}
  end

  test "desired state mirrors physical state updates for now" do
    _ = PhysicalState.put(:light, 2, %{power: :on, brightness: 25})

    assert DesiredState.get(:light, 2) == %{power: :on, brightness: 25}
  end

  test "commit returns diffs for changed values" do
    _ = PhysicalState.put(:light, 3, %{power: :on, brightness: 10, kelvin: 3000})

    txn =
      DesiredState.begin("scene-2")
      |> DesiredState.apply(:light, 3, %{brightness: 80})

    {:ok, diff, _updated} = DesiredState.commit(txn)

    assert diff[{:light, 3}] == %{brightness: 80}
  end
end
