defmodule Hueworks.Control.ApplyTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{Apply, DesiredState, TraceBuffer}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, Area}

  setup do
    TraceBuffer.clear()

    original_executor_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    Application.put_env(:hueworks, :control_executor_enabled, false)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_executor_enabled)
    end)

    :ok
  end

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

  test "commit_and_enqueue returns invalid area errors unchanged" do
    txn =
      :scene_a
      |> DesiredState.begin()
      |> DesiredState.apply(:light, 3, %{power: :on})

    assert {:error, {:invalid_area_id, :bad_area}} =
             Apply.commit_and_enqueue(txn, :bad_area, enqueue_mode: :append)
  end

  test "records structured intent, planning, and enqueue evidence for traced control work" do
    area = Repo.insert!(%Area{name: "Trace Area"})

    bridge =
      insert_bridge!(%{
        name: "Trace Bridge",
        type: :hue,
        host: "trace-bridge",
        credentials: %{}
      })

    light =
      Repo.insert!(%Light{
        name: "Trace Light",
        source: :hue,
        source_id: "trace-light",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    txn =
      :scene_a
      |> DesiredState.begin()
      |> DesiredState.apply(:light, light.id, %{power: :on, brightness: 55})

    trace = %{
      trace_id: "api-control-plan-1",
      source: "api.manual_control",
      area_id: area.id,
      started_at_ms: System.monotonic_time(:millisecond)
    }

    assert {:ok, %{plan: [%{id: light_id}]}} =
             Apply.commit_and_enqueue(txn, area.id, trace: trace)

    assert light_id == light.id

    assert %{events: events} = TraceBuffer.recent(trace_id: "api-control-plan-1")

    entity_events = Enum.reject(events, &(is_nil(&1.entity_kind) and is_nil(&1.entity_id)))

    assert Enum.map(entity_events, & &1.stage) == [:enqueued, :planned, :intent]
    assert Enum.all?(entity_events, &(&1.entity_kind == :light and &1.entity_id == light.id))
    assert Enum.at(entity_events, 1).planner_ms >= 0
    assert Enum.at(entity_events, 0).action_count == 1
    assert Enum.any?(events, &(&1.action_count == 1 and &1.bridge_count == 1))
  end
end
