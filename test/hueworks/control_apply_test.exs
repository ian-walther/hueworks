defmodule Hueworks.Control.ApplyTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{Apply, DesiredState}

  test "commit_transaction merges intent and reconcile diffs by default" do
    txn =
      :scene_a
      |> DesiredState.begin()
      |> DesiredState.apply(:light, 1, %{power: :on, brightness: 40})

    assert {:ok, result} = Apply.commit_transaction(txn)
    assert result.intent_diff == %{{:light, 1} => %{power: :on, brightness: 40}}
    assert result.reconcile_diff == %{{:light, 1} => %{power: :on, brightness: 40}}
    assert result.plan_diff == %{{:light, 1} => %{power: :on, brightness: 40}}
  end

  test "commit_transaction uses raw transaction changes when force_apply is true" do
    txn =
      :scene_a
      |> DesiredState.begin()
      |> DesiredState.apply(:light, 2, %{power: :off})

    assert {:ok, result} = Apply.commit_transaction(txn, force_apply: true)
    assert result.plan_diff == %{{:light, 2} => %{power: :off}}
  end

  test "commit_and_enqueue returns invalid room errors unchanged" do
    txn =
      :scene_a
      |> DesiredState.begin()
      |> DesiredState.apply(:light, 3, %{power: :on})

    assert {:error, {:invalid_room_id, :bad_room}} =
             Apply.commit_and_enqueue(txn, :bad_room, enqueue_mode: :append)
  end
end
