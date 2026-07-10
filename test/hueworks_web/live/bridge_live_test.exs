defmodule HueworksWeb.BridgeLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  setup do
    previous_modules = Application.get_env(:hueworks, :connection_test_modules)
    previous_test_pid = Application.get_env(:hueworks, :bridge_live_test_pid)

    on_exit(fn ->
      restore_app_env(:hueworks, :connection_test_modules, previous_modules)
      restore_app_env(:hueworks, :bridge_live_test_pid, previous_test_pid)
    end)

    :ok
  end

  test "renders z2m fields when type is selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridge/new")

    html =
      render_change(view, "update_bridge", %{
        "type" => "z2m",
        "host" => "10.0.0.55",
        "z2m_broker_port" => "1883",
        "z2m_base_topic" => "zigbee2mqtt"
      })

    assert html =~ "MQTT Port"
    assert html =~ "MQTT Username (optional)"
    assert html =~ "Base Topic"
  end

  test "validates z2m required fields before running connection test", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridge/new")

    render_change(view, "update_bridge", %{
      "type" => "z2m",
      "host" => "10.0.0.56",
      "z2m_broker_port" => "0",
      "z2m_base_topic" => ""
    })

    html = render_click(view, "test_bridge", %{})

    assert html =~ "Missing required fields: z2m_broker_port, z2m_base_topic"
  end

  test "connection test shows a testing state before resolving asynchronously", %{conn: conn} do
    Application.put_env(:hueworks, :connection_test_modules, %{
      ha: HueworksWeb.BridgeLiveTest.BlockingHomeAssistant
    })

    Application.put_env(:hueworks, :bridge_live_test_pid, self())

    {:ok, view, _html} = live(conn, "/config/bridge/new")

    render_change(view, "update_bridge", %{
      "type" => "ha",
      "host" => "ha.local",
      "ha_token" => "token"
    })

    html = render_click(view, "test_bridge", %{})

    assert html =~ "Testing connection"
    assert html =~ "disabled"
    assert_receive {:bridge_test_started, test_pid}

    send(test_pid, :finish_bridge_test)

    html = render_async(view)
    assert html =~ "Connection verified."
  end

  test "creates a z2m bridge after a successful connection test", %{conn: conn} do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    acceptor =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    on_exit(fn ->
      if Process.alive?(acceptor), do: Process.exit(acceptor, :kill)
      :gen_tcp.close(listener)
    end)

    {:ok, view, _html} = live(conn, "/config/bridge/new")

    render_change(view, "update_bridge", %{
      "type" => "z2m",
      "host" => "127.0.0.1",
      "z2m_broker_port" => Integer.to_string(port),
      "z2m_base_topic" => "zigbee2mqtt"
    })

    render_click(view, "test_bridge", %{})
    html = render_async(view)
    assert html =~ "Connection verified."

    assert {:error, {:live_redirect, %{to: to}}} =
             render_click(view, "proceed_bridge", %{})

    bridge = Repo.get_by!(Bridge, host: "127.0.0.1", type: :z2m)
    assert to == "/config/bridge/#{bridge.id}/setup"
    assert bridge.import_complete == false
    assert bridge.enabled == true
  end

  test "cannot proceed before running a successful connection test", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridge/new")

    render_change(view, "update_bridge", %{
      "type" => "ha",
      "host" => "ha.local",
      "ha_token" => "token"
    })

    html = render_click(view, "proceed_bridge", %{})

    assert html =~ "Run Test before proceeding."
    refute Repo.get_by(Bridge, host: "ha.local", type: :ha)
  end

  test "unsupported bridge types are rejected before saving", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridge/new")

    render_change(view, "update_bridge", %{
      "type" => "oops",
      "host" => "bridge.local"
    })

    :sys.replace_state(view.pid, fn state ->
      put_in(state.socket.assigns.test_status, :ok)
    end)

    html = render_click(view, "proceed_bridge", %{})

    assert html =~ "Unsupported bridge type."
    refute Repo.get_by(Bridge, host: "bridge.local")
  end
end

defmodule HueworksWeb.BridgeLiveTest.BlockingHomeAssistant do
  def test(_host, _token) do
    test_pid = Application.fetch_env!(:hueworks, :bridge_live_test_pid)
    send(test_pid, {:bridge_test_started, self()})

    receive do
      :finish_bridge_test -> {:ok, "Async Home Assistant"}
    after
      1_000 -> {:error, "timed out waiting for test"}
    end
  end
end
