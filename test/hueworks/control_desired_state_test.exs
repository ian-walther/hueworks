defmodule Hueworks.Control.DesiredStateTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.DesiredState

  test "put canonicalizes state keys at the desired-state boundary" do
    assert DesiredState.put(:light, 20_001, %{
             "power" => "off",
             "brightness" => 42,
             "temperature" => 2800
           }) == %{power: :off}
  end

  test "transaction apply canonicalizes state keys at the desired-state boundary" do
    txn =
      :scene
      |> DesiredState.begin()
      |> DesiredState.apply(:light, 20_002, %{
        "power" => "on",
        "brightness" => 42,
        "temperature" => 2800
      })

    assert {:ok, result} = DesiredState.commit(txn)
    assert result.updated == %{{:light, 20_002} => %{power: :on, brightness: 42, kelvin: 2800}}
  end
end
