defmodule Hueworks.Control.ExecutorConvergenceTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, Executor, State}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, Room}

  setup do
    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_delay = Application.get_env(:hueworks, :control_executor_convergence_delay_ms)
    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_convergence_delay_ms, 10)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_convergence_delay_ms, original_delay)
    end)

    :ok
  end

  test "executor schedules recovery work when desired state still does not match physical state" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_convergence_retry,
         dispatch_fun: dispatch_fun,
         bridge_rate_fun: fn _ -> 20 end}
      )

    room = Repo.insert!(%Room{name: "Convergence Retry Room"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.80",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Retry Lamp",
        source: :hue,
        source_id: "retry-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    light_id = light.id

    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [%{type: :light, id: light.id, bridge_id: bridge.id, desired: %{power: :on}}],
               server: :executor_convergence_retry,
               mode: :replace
             )

    Executor.tick(:executor_convergence_retry, force: true)
    assert_receive {:dispatched, %{id: ^light_id, attempts: 0}}, 500

    Process.sleep(30)
    Executor.tick(:executor_convergence_retry, force: true)
    assert_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 500
  end

  test "executor does not schedule recovery work once physical state catches up" do
    parent = self()

    dispatch_fun = fn action ->
      send(parent, {:dispatched, action})
      :ok
    end

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :executor_convergence_ok,
         dispatch_fun: dispatch_fun,
         bridge_rate_fun: fn _ -> 20 end}
      )

    room = Repo.insert!(%Room{name: "Convergence OK Room"})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.81",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "OK Lamp",
        source: :hue,
        source_id: "ok-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    light_id = light.id

    _ = DesiredState.put(:light, light.id, %{power: :on})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok ==
             Executor.enqueue(
               [%{type: :light, id: light.id, bridge_id: bridge.id, desired: %{power: :on}}],
               server: :executor_convergence_ok,
               mode: :replace
             )

    Executor.tick(:executor_convergence_ok, force: true)
    assert_receive {:dispatched, %{id: ^light_id, attempts: 0}}, 500

    _ = State.put(:light, light.id, %{power: :on})

    Process.sleep(30)
    Executor.tick(:executor_convergence_ok, force: true)
    refute_receive {:dispatched, %{id: ^light_id, attempts: 1}}, 200
  end
end
