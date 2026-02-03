defmodule Hueworks.Control.ExecutorTest do
  use Hueworks.DataCase, async: true

  alias Hueworks.Control.Executor

  test "commands_for_action drops brightness/kelvin when off" do
    action = %{desired: %{power: :off, brightness: 20, kelvin: 4000}}
    assert Executor.commands_for_action(action) == [:off]
  end

  test "commands_for_action includes on, brightness, and color temp" do
    action = %{desired: %{power: :on, brightness: "25", kelvin: 3000}}
    assert Executor.commands_for_action(action) == [:on, {:brightness, 25}, {:color_temp, 3000}]
  end

  test "commands_for_action includes brightness without power" do
    action = %{desired: %{brightness: 55}}
    assert Executor.commands_for_action(action) == [{:brightness, 55}]
  end
end
