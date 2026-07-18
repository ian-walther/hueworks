defmodule Hueworks.RuntimeIOTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.Pipeline
  alias Hueworks.RuntimeIO

  setup do
    previous = Application.get_env(:hueworks, :runtime_io_disabled)
    previous_bootstrap = Application.get_env(:hueworks, :control_state_bootstrap_modules)
    previous_pid = Application.get_env(:hueworks, :runtime_io_test_pid)

    on_exit(fn ->
      restore_app_env(:hueworks, :runtime_io_disabled, previous)
      restore_app_env(:hueworks, :control_state_bootstrap_modules, previous_bootstrap)
      restore_app_env(:hueworks, :runtime_io_test_pid, previous_pid)
    end)

    :ok
  end

  test "disabled application children retain data and web services but omit every runtime transport" do
    ids =
      true
      |> Hueworks.Application.children()
      |> Enum.map(&Supervisor.child_spec(&1, []).id)

    assert Hueworks.Repo in ids
    assert Phoenix.PubSub.Supervisor in ids
    assert HueworksApp.Cache.Store in ids
    assert Hueworks.Control.State in ids
    assert Hueworks.Control.DesiredState in ids
    assert Hueworks.Control.TraceBuffer in ids
    assert HueworksWeb.Endpoint in ids

    refute Hueworks.Control.Executor in ids
    refute Hueworks.Control.CircadianPoller in ids
    refute Hueworks.Subscription.HueEventStream in ids
    refute Hueworks.Subscription.HomeAssistantEventStream in ids
    refute Hueworks.Subscription.CasetaEventStream in ids
    refute Hueworks.Subscription.Z2MEventStream in ids
    refute Hueworks.HomeAssistant.Export in ids
    refute Hueworks.HomeKit.Bridge in ids
  end

  test "disabled mode blocks ad hoc bridge fetches in addition to supervised workers" do
    Application.put_env(:hueworks, :runtime_io_disabled, true)

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "Home Assistant",
        host: "this-host-must-not-be-contacted.invalid:8123",
        credentials: %{token: "secret"}
      })

    assert RuntimeIO.disabled?()
    assert {:error, :runtime_io_disabled} = Pipeline.fetch_raw(bridge)
    assert {:error, :runtime_io_disabled} = Pipeline.create_import(bridge)
  end

  test "physical-state bootstrap is inert while runtime I/O is disabled" do
    Application.put_env(:hueworks, :runtime_io_disabled, true)
    Application.put_env(:hueworks, :control_state_bootstrap_modules, [__MODULE__.BootstrapProbe])
    Application.put_env(:hueworks, :runtime_io_test_pid, self())

    assert :ok = Hueworks.Control.State.bootstrap()
    refute_receive :bootstrap_ran, 30
  end

  defmodule BootstrapProbe do
    def run do
      send(Application.fetch_env!(:hueworks, :runtime_io_test_pid), :bootstrap_ran)
    end
  end
end
