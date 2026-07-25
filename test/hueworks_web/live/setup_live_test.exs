defmodule HueworksWeb.SetupLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.{Onboarding, Repo}
  alias Hueworks.Schemas.{AppSetting, Area, Bridge, BridgeImport, ExternalSpace, Light}

  setup do
    previous_pipeline = Application.get_env(:hueworks, :onboarding_import_pipeline)
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)

    on_exit(fn ->
      restore_app_env(:hueworks, :onboarding_import_pipeline, previous_pipeline)
    end)

    :ok
  end

  test "first run offers HA-assisted and direct setup without trapping normal config", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/setup")

    assert has_element?(view, "#setup-path-choice", "Use Home Assistant to guide setup")
    assert has_element?(view, ".hw-setup-path-recommended", "Recommended")
    assert has_element?(view, "button[phx-value-path='ha_assisted']", "Start with Home Assistant")
    assert has_element?(view, "button[phx-value-path='direct']", "Set up HueWorks directly")
    assert has_element?(view, "a[href='/config']", "Leave for Config")
  end

  test "direct setup is a resumable checklist derived from committed data", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/setup")

    view
    |> element("button[phx-value-path='direct']")
    |> render_click()

    assert has_element?(view, "#setup-workspace[data-path='direct']")
    assert has_element?(view, "#setup-location[data-complete='false']", "Set location")

    assert has_element?(
             view,
             "#setup-location a[href='/config/general?return_to=setup']",
             "Open"
           )

    assert has_element?(
             view,
             "#setup-location-panel a[href='/config/general?return_to=setup']",
             "Configure location"
           )

    assert has_element?(view, "#setup-areas[data-complete='false']", "Create Areas")
    assert has_element?(view, "a[href='/config/bridges/new?type=hue']", "Add Hue")

    area = Repo.insert!(%Area{name: "Office"})
    Repo.insert!(%Hueworks.Schemas.Scene{name: "Auto", area_id: area.id})

    {:ok, resumed, _html} = live(conn, "/setup")
    assert has_element?(resumed, "#setup-areas[data-complete='true']")
    assert has_element?(resumed, "#setup-scene[data-complete='true']")
  end

  test "HA-assisted setup leads with the Home Assistant connection", %{conn: conn} do
    assert {:ok, _settings} = Onboarding.choose_path(:ha_assisted)

    {:ok, view, _html} = live(conn, "/setup")
    html = render(view)

    {home_assistant_position, _length} = :binary.match(html, ~s(id="home-assistant-setup"))
    {location_position, _length} = :binary.match(html, ~s(id="setup-location-panel"))

    assert home_assistant_position < location_position
    assert has_element?(view, "a[href='/config/bridges/new?type=ha']", "Add Home Assistant")
  end

  test "HA inventory is visible without materializing entities and links to focused Area design",
       %{
         conn: conn
       } do
    assert {:ok, _settings} = Onboarding.choose_path(:ha_assisted)
    bridge = insert_ha_inventory!()

    {:ok, view, _html} = live(conn, "/setup")

    assert has_element?(view, "#setup-workspace[data-path='ha_assisted']")
    assert has_element?(view, "#ha-inventory-#{bridge.id}", "1 floor")
    assert has_element?(view, "#setup-area-design-summary", "4 remain")
    assert has_element?(view, "a[href='/setup/areas']", "Review Area design")
    assert has_element?(view, "a[href*='type=hue'][href*='external_id=001788fffe111111']")
    assert has_element?(view, "a[href*='type=caseta'][href*='external_id=047a00fc']")
    assert has_element?(view, "a[href*='type=z2m'][href*='host=192.168.1.41']")

    refute has_element?(
             view,
             "#home-assistant-setup a[href='/config/bridges/new?type=ha']",
             "Add Home Assistant"
           )

    assert Repo.aggregate(Light, :count) == 0
  end

  test "inventory refresh runs asynchronously and explicitly remains non-materializing", %{
    conn: conn
  } do
    Application.put_env(:hueworks, :onboarding_import_pipeline, __MODULE__.InventoryPipeline)
    assert {:ok, _settings} = Onboarding.choose_path(:ha_assisted)

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.home:8123",
        credentials: %{"token" => "token"}
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/setup")

    view
    |> element("button[phx-click='refresh_ha_inventory'][phx-value-bridge_id='#{bridge.id}']")
    |> render_click()

    html = render_async(view)
    assert html =~ "Home Assistant inventory refreshed. No entities were imported."
    assert html =~ "Design HueWorks Areas"
    assert html =~ "1 remain"
    assert Repo.aggregate(Light, :count) == 0
  end

  test "new Home Assistant continuation refreshes inventory and advances to Area design", %{
    conn: conn
  } do
    Application.put_env(:hueworks, :onboarding_import_pipeline, __MODULE__.InventoryPipeline)
    assert {:ok, _settings} = Onboarding.choose_path(:ha_assisted)

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.home:8123",
        credentials: %{"token" => "token"}
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/setup?refresh_ha_inventory=#{bridge.id}")
    assert_redirect(view, "/setup/areas", 1_000)
    assert Repo.aggregate(BridgeImport, :count) == 1
    assert Repo.aggregate(ExternalSpace, :count) == 1
    assert Repo.aggregate(Light, :count) == 0
  end

  test "finish and dismiss are explicit and survive a new request", %{conn: conn} do
    assert {:ok, _settings} = Onboarding.choose_path(:direct)
    {:ok, view, _html} = live(conn, "/setup")

    view |> element("button[phx-click='finish_setup']") |> render_click()
    assert_redirect(view, "/control")
    assert Onboarding.status().finished?

    assert {:ok, _settings} = Onboarding.choose_path(:direct)
    {:ok, dismiss_view, _html} = live(conn, "/setup")

    dismiss_view |> element("button[phx-click='dismiss_setup']") |> render_click()
    assert_redirect(dismiss_view, "/config")
    assert Onboarding.status().dismissed?
  end

  defp insert_ha_inventory! do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "ha.home:8123",
        credentials: %{"token" => "token"}
      })
      |> Repo.insert!()

    Repo.insert!(%BridgeImport{
      bridge_id: bridge.id,
      raw_blob: %{
        "floors" => [],
        "areas" => [],
        "config_entries" => [
          %{
            "entry_id" => "hue-entry",
            "domain" => "hue",
            "title" => "Hue Bridge 001788111111"
          },
          %{
            "entry_id" => "caseta-entry",
            "domain" => "lutron_caseta",
            "title" => "047a00fc"
          },
          %{
            "entry_id" => "mqtt-entry",
            "domain" => "mqtt",
            "title" => "192.168.1.41"
          }
        ],
        "device_registry" => [
          %{
            "config_entries" => ["hue-entry"],
            "model" => "Hue Bridge",
            "identifiers" => [["hue", "001788fffe111111"]]
          }
        ]
      },
      normalized_blob: %{
        external_spaces: [
          %{kind: "ha_floor", external_id: "floor-1", name: "First Floor"},
          %{
            kind: "ha_area",
            external_id: "office",
            name: "Office",
            parent_kind: "ha_floor",
            parent_external_id: "floor-1"
          },
          %{
            kind: "ha_area",
            external_id: "kitchen",
            name: "Kitchen",
            parent_kind: "ha_floor",
            parent_external_id: "floor-1"
          },
          %{kind: "ha_area", external_id: "garage", name: "Garage"}
        ],
        areas: [],
        lights: [
          %{
            source_id: "light.office",
            space_refs: [%{kind: "ha_area", external_id: "office"}]
          },
          %{
            source_id: "light.kitchen",
            space_refs: [%{kind: "ha_area", external_id: "kitchen"}]
          }
        ],
        groups: []
      },
      review_blob: %{},
      status: :normalized,
      imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    {:ok, _design} = Hueworks.Onboarding.AreaDesign.refresh(bridge)

    bridge
  end

  defmodule InventoryPipeline do
    alias Hueworks.Repo
    alias Hueworks.Schemas.BridgeImport

    def create_import(bridge) do
      bridge_import =
        Repo.insert!(%BridgeImport{
          bridge_id: bridge.id,
          raw_blob: %{"floors" => [], "areas" => [], "config_entries" => []},
          normalized_blob: %{
            external_spaces: [
              %{kind: "ha_floor", external_id: "inventory-floor", name: "Inventory Floor"}
            ],
            areas: [],
            lights: [
              %{
                source_id: "light.not_materialized",
                space_refs: [%{kind: "ha_floor", external_id: "inventory-floor"}]
              }
            ],
            groups: []
          },
          review_blob: %{},
          status: :normalized,
          imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, bridge_import}
    end
  end
end
