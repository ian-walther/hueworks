defmodule Hueworks.Control.StateTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.State

  setup do
    original_modules = Application.get_env(:hueworks, :control_state_bootstrap_modules)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_state_bootstrap_modules, original_modules)
    end)

    :ok
  end

  test "putting xy state clears stale kelvin" do
    _ = State.put(:light, 10_001, %{power: :on, brightness: 55, kelvin: 3200})
    _ = State.put(:light, 10_001, %{x: 0.2211, y: 0.3322})

    state = State.get(:light, 10_001)

    assert state[:power] == :on
    assert state[:brightness] == 55
    assert state[:x] == 0.2211
    assert state[:y] == 0.3322
    refute Map.has_key?(state, :kelvin)
  end

  test "putting kelvin state clears stale xy" do
    _ = State.put(:light, 10_002, %{power: :on, brightness: 60, x: 0.2, y: 0.3})
    _ = State.put(:light, 10_002, %{kelvin: 3100})

    state = State.get(:light, 10_002)

    assert state[:power] == :on
    assert state[:brightness] == 60
    assert state[:kelvin] == 3100
    refute Map.has_key?(state, :x)
    refute Map.has_key?(state, :y)
  end

  test "bootstrap does not return until bootstrap modules finish" do
    ref = make_ref()

    Application.put_env(
      :hueworks,
      :control_state_bootstrap_modules,
      [{__MODULE__.BlockingBootstrapStub, {self(), ref}}]
    )

    task = Task.async(fn -> State.bootstrap() end)

    assert_receive {:bootstrap_started, ^ref, bootstrap_pid}, 100
    refute Task.yield(task, 20)

    send(bootstrap_pid, {:finish_bootstrap, ref})

    assert :ok == Task.await(task, 100)
    assert_receive {:bootstrap_finished, ^ref}, 100
  end

  defmodule BlockingBootstrapStub do
    def run({sink, ref}) do
      send(sink, {:bootstrap_started, ref, self()})

      receive do
        {:finish_bootstrap, ^ref} ->
          send(sink, {:bootstrap_finished, ref})
          :ok
      end
    end

    def run(_arg), do: :ok
  end
end
