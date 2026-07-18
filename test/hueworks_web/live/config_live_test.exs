defmodule HueworksWeb.ConfigLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.AppSettings
  alias Hueworks.HomeAssistant.Export
  alias Hueworks.Repo
  alias Hueworks.Scenes

  alias Hueworks.Schemas.{
    AppSetting,
    Bridge,
    Group,
    Light,
    LightState,
    PicoDevice,
    Room,
    Scene,
    SceneComponent
  }

  setup do
    original_tortoise = Application.get_env(:hueworks, :ha_export_tortoise_module)
    original_supervisor = Application.get_env(:hueworks, :ha_export_tortoise_supervisor_module)

    original_dynamic_supervisor =
      Application.get_env(:hueworks, :ha_export_dynamic_supervisor_module)

    original_supervisor_name = Application.get_env(:hueworks, :ha_export_tortoise_supervisor_name)
    original_pairing_state_module = Application.get_env(:hueworks, :homekit_pairing_state_module)
    original_pairing_stub = Application.get_env(:hueworks, :homekit_config_test_pairing)

    Application.put_env(:hueworks, :ha_export_tortoise_module, __MODULE__.TortoiseStub)

    Application.put_env(
      :hueworks,
      :ha_export_tortoise_supervisor_module,
      __MODULE__.SupervisorStub
    )

    Application.put_env(
      :hueworks,
      :ha_export_dynamic_supervisor_module,
      __MODULE__.DynamicSupervisorStub
    )

    Application.put_env(:hueworks, :ha_export_tortoise_supervisor_name, __MODULE__.SupervisorStub)
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairingStateStub)

    Application.put_env(:hueworks, :homekit_config_test_pairing, %{paired?: false, clear_count: 0})

    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    start_supervised!({Export, []})
    Export.reload()

    on_exit(fn ->
      restore_app_env(:hueworks, :ha_export_tortoise_module, original_tortoise)
      restore_app_env(:hueworks, :ha_export_tortoise_supervisor_module, original_supervisor)

      restore_app_env(
        :hueworks,
        :ha_export_dynamic_supervisor_module,
        original_dynamic_supervisor
      )

      restore_app_env(
        :hueworks,
        :ha_export_tortoise_supervisor_name,
        original_supervisor_name
      )

      restore_app_env(:hueworks, :homekit_pairing_state_module, original_pairing_state_module)
      restore_app_env(:hueworks, :homekit_config_test_pairing, original_pairing_stub)
    end)

    :ok
  end

  test "config overview is a status hub with links to focused sections", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config")

    assert html =~ "See what is connected"
    assert has_element?(view, "nav[aria-label='Configuration sections']")
    assert has_element?(view, "a[href='/config'][aria-current='page']", "Overview")
    assert has_element?(view, "a[href='/config/general']", "General")
    assert has_element?(view, "a[href='/config/bridges']", "Bridges")
    assert has_element?(view, "a[href='/config/light-states']", "Light States")
    assert has_element?(view, "a[href='/config/integrations']", "Integrations")
    assert has_element?(view, "nav[aria-label='Configuration sections'] .hw-config-content-frame")
    assert has_element?(view, "main.hw-config-content-frame")
    assert has_element?(view, "#system-status", "HueWorks 0.1.0")
    assert has_element?(view, "#system-status .hw-status-badge", "Healthy")
    refute html =~ "Save General Settings"
    refute html =~ "MQTT Password"
  end

  test "an empty installation shows a state-derived first-run checklist", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config")

    assert has_element?(view, "#first-run-checklist", "Set up HueWorks")
    assert has_element?(view, "#setup-step-general[data-complete='false']", "Set location")
    assert has_element?(view, "#setup-step-bridges[data-complete='false']", "Add a bridge")
    assert has_element?(view, "#setup-step-import[data-complete='false']", "Import entities")
    assert has_element?(view, "#setup-step-rooms[data-complete='false']", "Review rooms")
    assert has_element?(view, "#setup-step-scenes[data-complete='false']", "Create a scene")
  end

  test "the first-run checklist disappears after a useful setup exists", %{conn: conn} do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York"
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    bridge =
      Repo.insert!(%Bridge{
        type: :hue,
        name: "Hue Bridge",
        host: "192.0.2.10",
        credentials: %Bridge.Credentials{api_key: "test-key"},
        import_complete: true
      })

    room = Repo.insert!(%Room{name: "Living Room"})

    Repo.insert!(%Light{
      name: "Lamp",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      room_id: room.id
    })

    Repo.insert!(%Scene{name: "Auto", room_id: room.id})

    {:ok, view, _html} = live(conn, "/config")

    refute has_element?(view, "#first-run-checklist")
  end

  test "focused config pages keep their section active and show breadcrumbs", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    assert has_element?(view, "a[href='/config/general'][aria-current='page']", "General")
    assert has_element?(view, "nav[aria-label='Breadcrumb']", "Config")
  end

  test "shows global solar settings form and saves values", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config/general")

    assert html =~ "Location and transitions"
    assert html =~ "Save General Settings"
    assert html =~ "Default Transition (ms)"
    assert html =~ "Scale Transition By Brightness Delta"
    refute html =~ "Global solar settings saved."

    view
    |> form("form[phx-submit='save_global_solar']", %{
      "timezone" => "America/Chicago",
      "latitude" => "41.8781",
      "longitude" => "-87.6298",
      "default_transition_ms" => "900",
      "scale_transition_by_brightness" => "true"
    })
    |> render_submit()

    assert render(view) =~ "Global solar settings saved."

    settings = AppSettings.get_global()
    assert settings.latitude == 41.8781
    assert settings.longitude == -87.6298
    assert settings.timezone == "America/Chicago"
    assert settings.default_transition_ms == 900
    assert settings.scale_transition_by_brightness == true
  end

  test "shows a validation error for invalid solar input", %{conn: conn} do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      default_transition_ms: 900,
      scale_transition_by_brightness: false
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    {:ok, view, _html} = live(conn, "/config/general")

    view
    |> form("form[phx-submit='save_global_solar']", %{
      "timezone" => "America/Chicago",
      "latitude" => "41.8781",
      "longitude" => "-87.6298",
      "default_transition_ms" => "fast",
      "scale_transition_by_brightness" => "true"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "default_transition_ms must be an integer"

    settings = AppSettings.get_global()
    assert settings.default_transition_ms == 900
  end

  test "shows home assistant export settings form and saves values", %{conn: conn} do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      default_transition_ms: 0,
      scale_transition_by_brightness: false
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    {:ok, view, html} = live(conn, "/config/integrations")

    assert html =~ "Home Assistant MQTT Export"
    assert html =~ "Save Home Assistant"

    view
    |> form("form[phx-submit='save_ha_export']", %{
      "ha_export_scenes_enabled" => "true",
      "ha_export_room_selects_enabled" => "true",
      "ha_export_lights_enabled" => "true",
      "ha_export_mqtt_host" => "mqtt.local",
      "ha_export_mqtt_port" => "1883",
      "ha_export_mqtt_username" => "ha_user",
      "ha_export_mqtt_password" => "secret",
      "ha_export_discovery_prefix" => "homeassistant"
    })
    |> render_submit()

    assert render(view) =~ "Home Assistant MQTT export settings saved."

    settings = AppSettings.get_global()
    assert settings.ha_export_enabled == true
    assert settings.ha_export_scenes_enabled == true
    assert settings.ha_export_room_selects_enabled == true
    assert settings.ha_export_lights_enabled == true
    assert settings.ha_export_mqtt_host == "mqtt.local"
    assert settings.ha_export_mqtt_port == 1883
    assert settings.ha_export_mqtt_username == "ha_user"
    assert settings.ha_export_mqtt_password == "secret"
    assert settings.ha_export_discovery_prefix == "homeassistant"
  end

  test "saving home assistant export with a blank password preserves the stored password", %{
    conn: conn
  } do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      ha_export_enabled: true,
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: false,
      ha_export_lights_enabled: false,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_mqtt_port: 1883,
      ha_export_mqtt_username: "ha_user",
      ha_export_mqtt_password: "super-secret",
      ha_export_discovery_prefix: "homeassistant"
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    {:ok, view, _html} = live(conn, "/config/integrations")

    view
    |> form("form[phx-submit='save_ha_export']", %{
      "ha_export_scenes_enabled" => "true",
      "ha_export_room_selects_enabled" => "true",
      "ha_export_lights_enabled" => "false",
      "ha_export_mqtt_host" => "mqtt.local",
      "ha_export_mqtt_port" => "1883",
      "ha_export_mqtt_username" => "ha_user",
      "ha_export_mqtt_password" => "",
      "ha_export_discovery_prefix" => "homeassistant"
    })
    |> render_submit()

    settings = AppSettings.get_global()
    assert settings.ha_export_room_selects_enabled == true
    assert settings.ha_export_mqtt_password == "super-secret"
  end

  test "shows homekit bridge settings form and saves values", %{conn: conn} do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      default_transition_ms: 0,
      scale_transition_by_brightness: false
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    {:ok, view, html} = live(conn, "/config/integrations")

    assert html =~ "HomeKit Bridge"
    assert html =~ "Apple Home Setup Code"
    assert html =~ ~r/\d{3}-\d{2}-\d{3}/
    assert html =~ "Runtime disabled"
    refute html =~ "ready to pair"
    assert html =~ "Save HomeKit Bridge"
    assert html =~ "Reset Pairing"

    view
    |> form("form[phx-submit='save_homekit']", %{
      "homekit_bridge_name" => "HueWorks Test",
      "homekit_scenes_enabled" => "true"
    })
    |> render_submit()

    assert render(view) =~ "HomeKit bridge settings saved."

    settings = AppSettings.get_global()
    assert settings.homekit_bridge_name == "HueWorks Test"
    assert settings.homekit_scenes_enabled == true
  end

  test "homekit bridge settings can reset saved pairings", %{conn: conn} do
    Application.put_env(:hueworks, :homekit_config_test_pairing, %{
      paired?: true,
      clear_count: 1
    })

    {:ok, view, html} = live(conn, "/config/integrations")

    assert html =~ "paired"

    view
    |> element("#reset-homekit-pairings")
    |> render_click()

    html = render(view)
    assert html =~ "Reset 1 HomeKit pairing."
    assert html =~ "Runtime disabled"
  end

  test "AI API controls generate, reveal, disable, and rotate a persistent token", %{conn: conn} do
    {:ok, view, html} = live(conn, "/config/integrations")

    assert html =~ "AI API"
    assert html =~ "API access is disabled."
    refute html =~ "HUEWORKS_API_TOKEN"

    view
    |> element("#enable-ai-api")
    |> render_click()

    enabled_html = render(view)
    assert enabled_html =~ "API access is enabled."
    refute enabled_html =~ "HUEWORKS_API_TOKEN"
    refute enabled_html =~ AppSettings.get_global().api_token

    view
    |> element("#reveal-ai-api-token")
    |> render_click()

    revealed_html = render(view)
    assert revealed_html =~ "HUEWORKS_API_TOKEN"

    token = AppSettings.get_global().api_token
    assert revealed_html =~ token

    mcp_environment =
      revealed_html
      |> Floki.parse_document!()
      |> Floki.find("#ai-api-mcp-env")
      |> Floki.text()

    assert mcp_environment ==
             "HUEWORKS_API_URL=#{HueworksWeb.Endpoint.url()}\nHUEWORKS_API_TOKEN=#{token}"

    refute revealed_html =~ ~S({"\n"})

    assert has_element?(
             view,
             ".hw-api-value-row #copy-ai-api-token"
           )

    assert has_element?(
             view,
             ".hw-api-value-row #hide-ai-api-token"
           )

    view
    |> element("#rotate-ai-api-token")
    |> render_click()

    rotated_token = AppSettings.get_global().api_token
    refute rotated_token == token

    assert render(view) =~
             "API token rotated. Update the MCP configuration before using it again."

    view
    |> element("#disable-ai-api")
    |> render_click()

    assert AppSettings.get_global().api_enabled == false
    assert render(view) =~ "API access is disabled."
  end

  test "shows a validation error for invalid HA export input", %{conn: conn} do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      ha_export_enabled: true,
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: false,
      ha_export_lights_enabled: false,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_mqtt_port: 1883,
      ha_export_discovery_prefix: "homeassistant"
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    {:ok, view, _html} = live(conn, "/config/integrations")

    view
    |> form("form[phx-submit='save_ha_export']", %{
      "ha_export_scenes_enabled" => "true",
      "ha_export_room_selects_enabled" => "false",
      "ha_export_lights_enabled" => "false",
      "ha_export_mqtt_host" => "mqtt.local",
      "ha_export_mqtt_port" => "eighteen eighty three",
      "ha_export_mqtt_username" => "ha_user",
      "ha_export_mqtt_password" => "secret",
      "ha_export_discovery_prefix" => "homeassistant"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "ha_export_mqtt_port must be an integer"

    settings = AppSettings.get_global()
    assert settings.ha_export_mqtt_port == 1883
  end

  test "republish button is available for enabled HA export and shows status", %{conn: conn} do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/New_York",
      ha_export_enabled: true,
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: false,
      ha_export_lights_enabled: false,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_mqtt_port: 1883,
      ha_export_discovery_prefix: "homeassistant"
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    {:ok, view, html} = live(conn, "/config/integrations")

    assert html =~ "Republish Exported Entities"

    view
    |> element("button[phx-click='republish_ha_export_entities']")
    |> render_click()

    assert render(view) =~ "Republished exported Home Assistant entities."
  end

  test "shows light state actions and list entries", %{conn: conn} do
    {:ok, _manual} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})
    {:ok, _circadian} = Scenes.create_light_state("Circadian A", :circadian, %{})

    {:ok, _view, html} = live(conn, "/config/light-states")

    assert html =~ "New Manual"
    assert html =~ "New Circadian"
    assert html =~ "Soft (manual temp)"
    assert html =~ "Circadian A (circadian)"
  end

  test "shows manual color labels for atom-keyed manual configs", %{conn: conn} do
    Repo.insert!(%LightState{
      name: "Blue",
      type: :manual,
      config: %{mode: :color, brightness: 75, hue: 210, saturation: 60}
    })

    {:ok, _view, html} = live(conn, "/config/light-states")

    assert html =~ "Blue (manual color)"
  end

  test "duplicate light state action navigates to the copied editor", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})

    {:ok, view, _html} = live(conn, "/config/light-states")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> element("button[phx-click='duplicate_light_state'][phx-value-id='#{state.id}']")
             |> render_click()

    copy = Repo.get_by!(LightState, name: "Soft Copy")
    assert to == "/config/light-states/#{copy.id}/edit"
  end

  test "delete light state removes unused state from the list", %{conn: conn} do
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})

    {:ok, view, _html} = live(conn, "/config/light-states")

    assert has_element?(
             view,
             "button[phx-click='delete_light_state'][phx-value-id='#{state.id}'][data-confirm*='Soft (manual temp)']"
           )

    assert has_element?(
             view,
             "button[phx-click='delete_light_state'][phx-value-id='#{state.id}'][data-confirm*='cannot be undone']"
           )

    view
    |> element("button[phx-click='delete_light_state'][phx-value-id='#{state.id}']")
    |> render_click()

    refute Repo.get(LightState, state.id)
    refute render(view) =~ "Soft (manual temp)"
  end

  test "delete light state is disabled and shows usage info when in use", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Studio", metadata: %{}})
    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    Repo.insert!(%SceneComponent{
      name: "Component 1",
      scene_id: scene.id,
      light_state_id: state.id
    })

    {:ok, view, html} = live(conn, "/config/light-states")

    assert html =~ "Studio / Chill"

    assert has_element?(
             view,
             "button[phx-click='delete_light_state'][phx-value-id='#{state.id}'][disabled]"
           )
  end

  test "handles geolocation event by prefilling lat/lon and timezone", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/config/general")

    render_hook(view, "geolocation_success", %{
      "latitude" => 40.7128,
      "longitude" => -74.0060,
      "timezone" => "America/New_York"
    })

    html = render(view)
    assert html =~ "Location and timezone received from browser."
    assert html =~ "40.712800"
    assert html =~ "-74.006000"
    assert html =~ ~s(value="America/New_York" selected)
  end

  test "shows the complete IANA timezone list and preserves the selected zone", %{
    conn: conn
  } do
    Repo.insert!(%AppSetting{
      scope: "global",
      latitude: 40.7128,
      longitude: -74.0060,
      timezone: "America/Indiana/Indianapolis",
      default_transition_ms: 750,
      scale_transition_by_brightness: true,
      ha_export_enabled: true,
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: true,
      ha_export_lights_enabled: false,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_mqtt_port: 1884,
      ha_export_mqtt_username: "ha_user",
      ha_export_mqtt_password: "secret",
      ha_export_discovery_prefix: "custom_ha"
    })

    HueworksApp.Cache.flush_namespace(:app_settings)

    {:ok, _view, html} = live(conn, "/config/general")

    assert html =~ ~s(value="America/Indiana/Indianapolis")
    assert html =~ ~s(value="Pacific/Chatham")
    assert html =~ ~s(value="Africa/Abidjan")
    assert html =~ ~s(value="750")
    assert html =~ ~s(id="global_scale_transition_by_brightness")
    assert html =~ ~s(checked)

    assert html =~
             ~r/<option[^>]*value="America\/Indiana\/Indianapolis"[^>]*selected/

    {:ok, _view, integrations_html} = live(conn, "/config/integrations")
    assert integrations_html =~ ~s(id="ha_export_scenes_enabled")
    assert integrations_html =~ ~s(id="ha_export_room_selects_enabled")
    assert integrations_html =~ ~s(value="mqtt.local")
    assert integrations_html =~ ~s(value="1884")
    assert integrations_html =~ ~s(value="ha_user")
    assert integrations_html =~ ~s(value="custom_ha")
  end

  test "shows Scene Import button for Home Assistant bridges", %{conn: conn} do
    insert_bridge!(%{
      type: :ha,
      name: "Home Assistant",
      host: "10.0.0.90",
      credentials: %{"token" => "token"},
      enabled: true,
      import_complete: true
    })

    {:ok, _view, html} = live(conn, "/config/bridges")

    assert html =~ "Scene Import"
    assert html =~ "/config/bridges/"
    assert html =~ "/external-scenes"
  end

  test "delete entities removes imported bridge entities but keeps the bridge", %{conn: conn} do
    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.95",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    room = Repo.insert!(%Room{name: "Studio", metadata: %{}})

    Repo.insert!(%Light{
      name: "Lamp",
      source: :caseta,
      source_id: "42",
      bridge_id: bridge.id,
      room_id: room.id,
      enabled: true
    })

    Repo.insert!(%Group{
      name: "Overhead",
      source: :caseta,
      source_id: "group-42",
      bridge_id: bridge.id,
      room_id: room.id,
      enabled: true
    })

    Repo.insert!(%PicoDevice{
      bridge_id: bridge.id,
      room_id: room.id,
      source_id: "device-1",
      name: "Main Floor Pico",
      hardware_profile: "5_button",
      metadata: %{}
    })

    {:ok, view, _html} = live(conn, "/config/bridges")

    assert has_element?(
             view,
             "button[phx-click='delete_entities'][phx-value-id='#{bridge.id}'][data-confirm]"
           )

    view
    |> element("button[phx-click='delete_entities'][phx-value-id='#{bridge.id}']")
    |> render_click()

    assert Repo.get(Bridge, bridge.id)
    assert Repo.aggregate(Light, :count) == 0
    assert Repo.aggregate(Group, :count) == 0
    assert Repo.aggregate(PicoDevice, :count) == 0
    refute render(view) =~ "Delete Entities"
  end

  test "delete bridge removes the bridge from config", %{conn: conn} do
    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.96",
        credentials: %{"api_key" => "key"},
        enabled: true,
        import_complete: false
      })

    {:ok, view, _html} = live(conn, "/config/bridges")

    assert has_element?(
             view,
             "button[phx-click='delete_bridge'][phx-value-id='#{bridge.id}'][data-confirm]"
           )

    view
    |> element("button[phx-click='delete_bridge'][phx-value-id='#{bridge.id}']")
    |> render_click()

    refute Repo.get(Bridge, bridge.id)
    refute render(view) =~ "Hue Bridge"
  end

  defmodule TortoiseStub do
    def publish(_client_id, _topic, _payload, _opts), do: :ok
  end

  defmodule SupervisorStub do
    def start_child(_opts) do
      {:ok,
       spawn(fn ->
         receive do
         after
           :infinity -> :ok
         end
       end)}
    end
  end

  defmodule DynamicSupervisorStub do
    def terminate_child(_name, pid) when is_pid(pid) do
      Process.exit(pid, :kill)
      :ok
    end
  end

  defmodule PairingStateStub do
    def paired?(_data_path) do
      Application.get_env(:hueworks, :homekit_config_test_pairing, %{})
      |> Map.get(:paired?, false)
    end

    def clear_pairings(_data_path) do
      pairing = Application.get_env(:hueworks, :homekit_config_test_pairing, %{})
      count = Map.get(pairing, :clear_count, 0)

      Application.put_env(
        :hueworks,
        :homekit_config_test_pairing,
        Map.put(pairing, :paired?, false)
      )

      {:ok, count}
    end
  end
end
