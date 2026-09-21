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

  test "physical power off keeps last-known levels" do
    _ = State.put(:light, 10_004, %{power: :on, brightness: 60, kelvin: 3100})
    _ = State.put(:light, 10_004, %{power: :off})

    assert State.get(:light, 10_004) == %{power: :off, brightness: 60, kelvin: 3100}
  end

  test "snapshot writes compare opaque observation versions and only publish accepted observations" do
    Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
    assert State.observation_version(:light, 10_007) == nil

    assert {:ok, %{brightness: 10}} =
             State.put_if_unobserved_since(:light, 10_007, %{brightness: 10}, nil)

    first = State.observation_version(:light, 10_007)
    assert is_reference(first)
    assert_receive {:control_state, :light, 10_007, %{brightness: 10}}
    State.put(:light, 10_007, %{brightness: 80})
    assert_receive {:control_state, :light, 10_007, %{brightness: 80}}
    second = State.observation_version(:light, 10_007)
    assert first != second
    assert :superseded = State.put_if_unobserved_since(:light, 10_007, %{brightness: 25}, first)
    refute_receive {:control_state, :light, 10_007, _}
    assert %{brightness: 80} = State.get(:light, 10_007)
    assert %DateTime{} = State.observed_at(:light, 10_007)
  end

  test "put canonicalizes state keys at the physical-state boundary" do
    assert State.put(:light, 10_006, %{"power" => "off", "brightness" => 25}) == %{
             power: :off,
             brightness: 25
           }
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

  test "put does not block while automatic bootstrap is running" do
    ref = make_ref()

    Application.put_env(
      :hueworks,
      :control_state_bootstrap_modules,
      [{__MODULE__.BlockingBootstrapStub, {self(), ref}}]
    )

    old_pid = Process.whereis(State)
    Process.exit(old_pid, :kill)

    assert_receive {:bootstrap_started, ^ref, bootstrap_pid}, 500

    task =
      Task.async(fn ->
        State.put(:light, 10_003, %{power: :off, brightness: 1})
      end)

    assert %{power: :off, brightness: 1} == Task.await(task, 100)

    send(bootstrap_pid, {:finish_bootstrap, ref})
    assert_receive {:bootstrap_finished, ^ref}, 500
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
