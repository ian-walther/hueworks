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

    {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: _updated}} =
      DesiredState.commit(txn)

    assert intent_diff[{:light, 1}] == %{power: :off}
    assert reconcile_diff[{:light, 1}] == %{power: :off}
    assert DesiredState.get(:light, 1) == %{power: :off}
  end

  test "physical state updates do not overwrite desired state" do
    _ = DesiredState.put(:light, 2, %{power: :on, brightness: 60, kelvin: 3000})

    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.insert(:hueworks_control_state, {{:light, 2}, %{power: :on, brightness: 25}})
    end

    assert DesiredState.get(:light, 2) == %{power: :on, brightness: 60, kelvin: 3000}
  end

  test "commit returns intent and reconcile diffs" do
    _ = PhysicalState.put(:light, 3, %{power: :on, brightness: 10, kelvin: 3000})
    _ = DesiredState.put(:light, 3, %{power: :on, brightness: 20, kelvin: 3000})

    txn =
      DesiredState.begin("scene-2")
      |> DesiredState.apply(:light, 3, %{brightness: 80})

    {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: _updated}} =
      DesiredState.commit(txn)

    assert intent_diff[{:light, 3}] == %{brightness: 80}
    assert reconcile_diff[{:light, 3}] == %{brightness: 80}
  end

  test "commit treats numeric strings and numeric values as equal for brightness and kelvin" do
    _ = PhysicalState.put(:light, 4, %{power: :on, brightness: 27, kelvin: 2000})

    txn =
      DesiredState.begin("scene-3")
      |> DesiredState.apply(:light, 4, %{power: :on, brightness: "27", kelvin: "2000"})

    {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: _updated}} =
      DesiredState.commit(txn)

    assert intent_diff[{:light, 4}] == %{power: :on, brightness: "27", kelvin: "2000"}
    assert reconcile_diff == %{}
  end

  test "commit treats small brightness drift as equal for reconcile diff" do
    _ = PhysicalState.put(:light, 5, %{power: :on, brightness: 47, kelvin: 3000})

    txn =
      DesiredState.begin("scene-4")
      |> DesiredState.apply(:light, 5, %{power: :on, brightness: 46, kelvin: 3000})

    {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: _updated}} =
      DesiredState.commit(txn)

    assert intent_diff[{:light, 5}] == %{power: :on, brightness: 46, kelvin: 3000}
    assert reconcile_diff == %{}
  end

  test "commit does not treat small brightness changes as equal for intent diff" do
    _ = PhysicalState.put(:light, 6, %{power: :on, brightness: 86, kelvin: 3000})
    _ = DesiredState.put(:light, 6, %{power: :on, brightness: 86, kelvin: 3000})

    txn =
      DesiredState.begin("scene-5")
      |> DesiredState.apply(:light, 6, %{power: :on, brightness: 87, kelvin: 3000})

    {:ok, %{intent_diff: intent_diff, reconcile_diff: reconcile_diff, updated: _updated}} =
      DesiredState.commit(txn)

    assert intent_diff[{:light, 6}] == %{brightness: 87}
    assert reconcile_diff == %{}
  end
end
