defmodule HueworksWeb.BridgeLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

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

    html = render_click(view, "test_bridge", %{})
    assert html =~ "Connection verified."

    assert {:error, {:live_redirect, %{to: to}}} =
             render_click(view, "proceed_bridge", %{})

    bridge = Repo.get_by!(Bridge, host: "127.0.0.1", type: :z2m)
    assert to == "/config/bridge/#{bridge.id}/setup"
    assert bridge.import_complete == false
    assert bridge.enabled == true
  end
end
