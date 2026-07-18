defmodule HueworksWeb.BridgeLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.AppSettings
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light}

  setup do
    previous_modules = Application.get_env(:hueworks, :connection_test_modules)
    previous_hue_onboarding = Application.get_env(:hueworks, :hue_onboarding_module)
    previous_ha_onboarding = Application.get_env(:hueworks, :ha_onboarding_module)
    previous_test_pid = Application.get_env(:hueworks, :bridge_live_test_pid)

    Application.put_env(
      :hueworks,
      :hue_onboarding_module,
      HueworksWeb.BridgeLiveTest.FailedHueOnboarding
    )

    Application.put_env(
      :hueworks,
      :ha_onboarding_module,
      HueworksWeb.BridgeLiveTest.HomeAssistantOnboarding
    )

    on_exit(fn ->
      restore_app_env(:hueworks, :connection_test_modules, previous_modules)
      restore_app_env(:hueworks, :hue_onboarding_module, previous_hue_onboarding)
      restore_app_env(:hueworks, :ha_onboarding_module, previous_ha_onboarding)
      restore_app_env(:hueworks, :bridge_live_test_pid, previous_test_pid)
    end)

    :ok
  end

  test "discovers and pairs a Hue bridge without asking for an API key", %{conn: conn} do
    Application.put_env(
      :hueworks,
      :hue_onboarding_module,
      HueworksWeb.BridgeLiveTest.HueOnboarding
    )

    {:ok, view, _html} = live(conn, "/config/bridges/new")
    html = render_async(view)

    assert html =~ "Office Hue"
    assert html =~ "192.168.1.10"
    assert html =~ "Press the link button"
    refute html =~ "Hue API Key"

    render_click(view, "pair_hue_bridge", %{
      "host" => "192.168.1.10",
      "external_id" => "001788fffe111111"
    })

    {to, _flash} = assert_redirect(view)

    bridge = Repo.get_by!(Bridge, external_id: "001788fffe111111", type: :hue)
    assert bridge.host == "192.168.1.10"
    assert Bridge.credentials_struct(bridge).api_key == "generated-key"
    assert to == "/config/bridges/#{bridge.id}/import"
  end

  test "does not offer to pair a discovered bridge that is already configured", %{conn: conn} do
    Application.put_env(
      :hueworks,
      :hue_onboarding_module,
      HueworksWeb.BridgeLiveTest.HueOnboarding
    )

    %Bridge{}
    |> Bridge.changeset(%{
      type: :hue,
      name: "Existing Hue",
      host: "192.168.1.10",
      external_id: "001788fffe111111",
      credentials: %{"api_key" => "existing-key"}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/config/bridges/new")
    html = render_async(view)

    assert html =~ "Already configured"
    refute html =~ ~s(phx-click="pair_hue_bridge")
  end

  test "keeps raw Hue credential entry behind a manual fallback", %{conn: conn} do
    Application.put_env(
      :hueworks,
      :hue_onboarding_module,
      HueworksWeb.BridgeLiveTest.FailedHueOnboarding
    )

    {:ok, view, _html} = live(conn, "/config/bridges/new")
    html = render_async(view)

    assert html =~ "No Hue bridges were discovered"
    refute html =~ "Hue API Key"

    html = render_click(view, "show_manual_hue", %{})
    assert html =~ "Hue API Key"
    assert html =~ "Use discovery instead"
  end

  test "warns before adding a native bridge after unlinked Home Assistant entities", %{conn: conn} do
    ha_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.local:8123",
        credentials: %{"token" => "token"},
        import_complete: true
      })
      |> Repo.insert!()

    %Light{}
    |> Light.changeset(%{
      name: "Mirrored Lamp",
      source: :ha,
      source_id: "light.mirrored_lamp",
      bridge_id: ha_bridge.id
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/config/bridges/new")

    assert has_element?(view, "#native-import-order-warning")

    assert has_element?(
             view,
             "#native-import-order-warning",
             "Home Assistant entities were imported first."
           )

    render_change(view, "update_bridge", %{"type" => "ha"})
    refute has_element?(view, "#native-import-order-warning")
  end

  test "discovers and selects a Home Assistant instance by stable identity", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridges/new")

    render_change(view, "update_bridge", %{"type" => "ha"})
    html = render_async(view)

    assert html =~ "Walther Home"
    assert html =~ "192.168.1.41:8123"
    refute html =~ "Home Assistant Token"

    html =
      render_click(view, "select_ha_instance", %{
        "host" => "192.168.1.41:8123",
        "external_id" => "1234567890abcdef"
      })

    assert html =~ "Home Assistant Token"
    assert has_element?(view, "#bridge_host[value='192.168.1.41:8123']")
  end

  test "marks a discovered Home Assistant instance that is already configured", %{conn: conn} do
    %Bridge{}
    |> Bridge.changeset(%{
      type: :ha,
      name: "Home Assistant",
      host: "old-address.local:8123",
      external_id: "1234567890abcdef",
      credentials: %{"token" => "existing-token"}
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/config/bridges/new")
    render_change(view, "update_bridge", %{"type" => "ha"})
    html = render_async(view)

    assert html =~ "Already configured"
    refute html =~ ~s(phx-click="select_ha_instance")
  end

  test "persists the selected Home Assistant identity after connection validation", %{conn: conn} do
    Application.put_env(:hueworks, :connection_test_modules, %{
      ha: HueworksWeb.BridgeLiveTest.SuccessfulHomeAssistant
    })

    {:ok, view, _html} = live(conn, "/config/bridges/new")

    render_change(view, "update_bridge", %{"type" => "ha"})
    render_async(view)

    render_click(view, "select_ha_instance", %{
      "host" => "192.168.1.41:8123",
      "external_id" => "1234567890abcdef"
    })

    render_change(view, "update_bridge", %{
      "type" => "ha",
      "host" => "192.168.1.41:8123",
      "ha_token" => "long-lived-token"
    })

    render_click(view, "test_bridge", %{})
    assert render_async(view) =~ "Connection verified."

    assert {:error, {:live_redirect, %{to: to}}} =
             render_click(view, "proceed_bridge", %{})

    bridge = Repo.get_by!(Bridge, type: :ha, external_id: "1234567890abcdef")
    assert bridge.host == "192.168.1.41:8123"
    assert Bridge.credentials_struct(bridge).token == "long-lived-token"
    assert to == "/config/bridges/#{bridge.id}/import"
  end

  test "renders z2m fields when type is selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridges/new")

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

  test "can reuse the existing Home Assistant export MQTT connection", %{conn: conn} do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.0,
        longitude: -75.0,
        ha_export_mqtt_host: "mqtt.local",
        ha_export_mqtt_port: 1884,
        ha_export_mqtt_username: "hueworks",
        ha_export_mqtt_password: "secret"
      })

    {:ok, view, _html} = live(conn, "/config/bridges/new")

    render_change(view, "update_bridge", %{"type" => "z2m"})
    html = render_click(view, "use_ha_export_mqtt", %{})

    assert html =~ "Copied the existing MQTT connection"
    assert has_element?(view, "#bridge_host[value='mqtt.local']")
    assert has_element?(view, "#z2m_broker_port[value='1884']")
    assert has_element?(view, "#z2m_username[value='hueworks']")
    assert has_element?(view, "#z2m_password[value='secret']")
    assert has_element?(view, "#z2m_base_topic[value='zigbee2mqtt']")
  end

  test "validates z2m required fields before running connection test", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridges/new")

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

    {:ok, view, _html} = live(conn, "/config/bridges/new")

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
    Application.put_env(:hueworks, :connection_test_modules, %{
      z2m: HueworksWeb.BridgeLiveTest.SuccessfulZ2M
    })

    {:ok, view, _html} = live(conn, "/config/bridges/new")

    render_change(view, "update_bridge", %{
      "type" => "z2m",
      "host" => "127.0.0.1",
      "z2m_broker_port" => "1883",
      "z2m_base_topic" => "zigbee2mqtt"
    })

    render_click(view, "test_bridge", %{})
    html = render_async(view)
    assert html =~ "Connection verified."

    assert {:error, {:live_redirect, %{to: to}}} =
             render_click(view, "proceed_bridge", %{})

    bridge = Repo.get_by!(Bridge, host: "127.0.0.1", type: :z2m)
    assert to == "/config/bridges/#{bridge.id}/import"
    assert bridge.import_complete == false
    assert bridge.enabled == true
  end

  test "cannot proceed before running a successful connection test", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/bridges/new")

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
    {:ok, view, _html} = live(conn, "/config/bridges/new")

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

defmodule HueworksWeb.BridgeLiveTest.SuccessfulZ2M do
  def test(_host, _opts), do: {:ok, "Zigbee2MQTT (1 device, 1 group)"}
end

defmodule HueworksWeb.BridgeLiveTest.SuccessfulHomeAssistant do
  def test(_host, _token), do: {:ok, "Home Assistant"}
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

defmodule HueworksWeb.BridgeLiveTest.HueOnboarding do
  alias Hueworks.BridgeOnboarding.Hue.Device

  def discover do
    {:ok,
     [
       %Device{
         id: "001788fffe111111",
         host: "192.168.1.10",
         name: "Office Hue",
         sources: [:mdns]
       }
     ]}
  end

  def pair("192.168.1.10", "001788fffe111111") do
    {:ok,
     %{
       api_key: "generated-key",
       name: "Office Hue",
       external_id: "001788fffe111111"
     }}
  end
end

defmodule HueworksWeb.BridgeLiveTest.HomeAssistantOnboarding do
  alias Hueworks.BridgeOnboarding.HomeAssistant.Device

  def discover do
    {:ok,
     [
       %Device{
         id: "1234567890abcdef",
         host: "192.168.1.41",
         port: 8123,
         name: "Walther Home"
       }
     ]}
  end
end

defmodule HueworksWeb.BridgeLiveTest.FailedHueOnboarding do
  def discover, do: {:error, "No Hue bridges were discovered on this network."}
  def pair(_host, _external_id), do: {:error, "pairing unavailable"}
end
