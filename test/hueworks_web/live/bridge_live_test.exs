defmodule HueworksWeb.BridgeLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
end
