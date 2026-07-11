defmodule Hueworks.ControlRuntimeDiagnosticsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.Executor.Trace
  alias Hueworks.Control.State
  alias Hueworks.Control.TraceBuffer

  defmodule RefreshBootstrapStub do
    def run(owner) do
      send(owner, {:refresh_bootstrap_started, self()})

      receive do
        :finish_refresh_bootstrap -> :ok
      end
    end
  end

  setup do
    TraceBuffer.clear()
    :ok
  end

  test "physical state records an observation timestamp without changing the state map" do
    assert nil == State.observed_at(:light, 71_001)

    State.put(:light, 71_001, %{power: :on, brightness: 41})

    assert %DateTime{} = State.observed_at(:light, 71_001)
    refute Map.has_key?(State.get(:light, 71_001), :observed_at)
  end

  test "desired state records an update timestamp only when intent changes" do
    assert nil == DesiredState.updated_at(:light, 71_002)

    DesiredState.put(:light, 71_002, %{power: :on})
    assert %DateTime{} = DesiredState.updated_at(:light, 71_002)
  end

  test "trace buffer keeps bounded safe events and filters them by target" do
    for sequence <- 1..1_002 do
      TraceBuffer.record(
        %{trace_id: "trace-#{sequence}", source: "test", room_id: 9},
        :planned,
        %{entity_kind: :light, entity_id: sequence, desired: %{power: :on}, planner_ms: 1}
      )
    end

    assert %{capacity: 1_000, retained_count: 1_000, events: [newest | _]} = TraceBuffer.recent()
    assert newest.trace_id == "trace-1002"
    assert newest.sequence == 1_002

    assert %{events: [event]} = TraceBuffer.recent(entity_kind: :light, entity_id: 1_002)
    assert event.stage == :planned
    assert event.desired == %{power: :on}
  end

  test "executor trace events become structured diagnostic evidence" do
    action = %{
      trace_id: "api-control-1",
      trace_source: "api.manual_control",
      trace_room_id: 9,
      type: :light,
      id: 71_003,
      bridge_id: 12,
      desired: %{power: :on, brightness: 44},
      enqueued_at_ms: 50,
      trace_started_at_ms: 10,
      attempts: 0
    }

    Trace.log_dispatch_start(action, 60, 2)
    Trace.log_dispatch_end(action, :ok, 60, 75)
    Trace.log_convergence_ok(action)

    assert %{events: events} = TraceBuffer.recent(trace_id: "api-control-1")

    assert Enum.map(events, & &1.stage) == [
             :converged,
             :dispatch_finished,
             :dispatch_started
           ]

    assert Enum.at(events, 1).desired == %{power: :on, brightness: 44}
    assert Enum.at(events, 1).result == :ok
  end

  test "trace summaries retain plan totals beyond the public event-list limit" do
    trace = %{trace_id: "api-large-plan-1", source: "api.scene_activate", room_id: 3}

    for id <- 1..150 do
      TraceBuffer.record(trace, :enqueued, %{
        type: :light,
        id: id,
        bridge_id: rem(id, 3) + 1,
        action_count: 150
      })
    end

    TraceBuffer.record(trace, :enqueued, %{action_count: 150, bridge_count: 3})

    assert %{action_count: 150, bridge_count: 3} = TraceBuffer.trace_summary("api-large-plan-1")
  end

  test "physical refresh schedules the existing bootstrap process without blocking the caller" do
    original_modules = Application.get_env(:hueworks, :control_state_bootstrap_modules)

    Application.put_env(:hueworks, :control_state_bootstrap_modules, [
      {RefreshBootstrapStub, self()}
    ])

    on_exit(fn ->
      restore_app_env(:hueworks, :control_state_bootstrap_modules, original_modules)
    end)

    assert :ok = State.refresh()
    assert_receive {:refresh_bootstrap_started, bootstrap_pid}
    send(bootstrap_pid, :finish_refresh_bootstrap)
  end
end
