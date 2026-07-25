defmodule HueworksWeb.SetupAreasLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.{ExternalSpaces, Repo}
  alias Hueworks.Schemas.{Area, Bridge, BridgeImport, ExternalSpaceIgnore, Light}

  setup do
    previous_area_design = Application.get_env(:hueworks, :onboarding_area_design_module)

    on_exit(fn ->
      restore_app_env(:hueworks, :onboarding_area_design_module, previous_area_design)
    end)

    :ok
  end

  test "requires Home Assistant inventory before presenting the work queue", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/setup/areas")

    assert has_element?(view, "a[href='/config/bridges/new?type=ha']", "Add Home Assistant")
    refute has_element?(view, "#area-design-work-queue")
  end

  test "a saved individual decision leaves the work queue and survives remount", %{conn: conn} do
    bridge = insert_ha_inventory!()
    destination = Repo.insert!(%Area{name: "Garage"})

    {:ok, view, _html} = live(conn, "/setup/areas")

    assert has_element?(view, "#area-design-progress", "4 decisions remain")
    assert has_element?(view, "#area-design-work-queue #ha-area-#{bridge.id}-garage")

    view
    |> form("#map-space-#{bridge.id}-garage", %{
      "target_area_id" => Integer.to_string(destination.id)
    })
    |> render_submit()

    refute has_element?(view, "#area-design-work-queue #ha-area-#{bridge.id}-garage")

    assert has_element?(
             view,
             "#area-design-completed-decisions #ha-area-#{bridge.id}-garage",
             "Mapped to Garage"
           )

    {:ok, resumed, _html} = live(conn, "/setup/areas")
    refute has_element?(resumed, "#area-design-work-queue #ha-area-#{bridge.id}-garage")
    assert ExternalSpaces.mapped_area_id(bridge, "ha_area", "garage") == destination.id
  end

  test "resolving a child Area keeps its Floor customizer open for the remaining work", %{
    conn: conn
  } do
    bridge = insert_ha_inventory!()
    {:ok, view, _html} = live(conn, "/setup/areas")

    render_submit(view, "create_area_for_space", %{
      "bridge_id" => Integer.to_string(bridge.id),
      "kind" => "ha_area",
      "external_id" => "office",
      "name" => "Office"
    })

    refute has_element?(
             view,
             "#area-design-work-queue #customize-floor-#{bridge.id}-floor-1 > .hw-floor-customizer-body > .hw-source-space-list #ha-area-#{bridge.id}-office"
           )

    assert has_element?(
             view,
             "#area-design-work-queue #customize-floor-#{bridge.id}-floor-1[open] #ha-area-#{bridge.id}-kitchen"
           )
  end

  test "ignoring a space is durable configuration rather than deleting its decision", %{
    conn: conn
  } do
    bridge = insert_ha_inventory!()
    {:ok, view, _html} = live(conn, "/setup/areas")

    view
    |> element(
      "#ha-area-#{bridge.id}-garage button[phx-click='skip_space'][phx-value-external_id='garage']"
    )
    |> render_click()

    refute has_element?(view, "#area-design-work-queue #ha-area-#{bridge.id}-garage")
    assert has_element?(view, "#area-design-completed-decisions", "Ignored")

    space = ExternalSpaces.get_by_identity(bridge, "ha_area", "garage")
    ignore = Repo.get_by!(ExternalSpaceIgnore, external_space_id: space.id)
    assert ignore.external_space_id == space.id
  end

  test "resolving a Floor moves the whole Floor to completed and imports no entities", %{
    conn: conn
  } do
    bridge = insert_ha_inventory!()
    {:ok, view, _html} = live(conn, "/setup/areas")

    html =
      render_submit(view, "use_floor_one", %{
        "bridge_id" => Integer.to_string(bridge.id),
        "external_id" => "floor-1",
        "name" => "Main Floor"
      })

    assert html =~ "Mapped First Floor and its HA Areas to Main Floor."
    refute has_element?(view, "#area-design-work-queue #ha-floor-#{bridge.id}-floor-1")

    assert has_element?(
             view,
             "#area-design-completed-decisions #ha-floor-#{bridge.id}-floor-1",
             "Combined into Main Floor"
           )

    refute has_element?(
             view,
             "#area-design-completed-decisions #floor-area-name-#{bridge.id}-floor-1"
           )

    assert has_element?(
             view,
             "#area-design-completed-decisions #ha-floor-#{bridge.id}-floor-1 button",
             "Keep as Main Floor"
           )

    assert Repo.aggregate(Light, :count) == 0
  end

  test "decision events do not resync source space facts", %{conn: conn} do
    bridge = insert_ha_inventory!()
    destination = Repo.insert!(%Area{name: "Garage"})
    {:ok, view, _html} = live(conn, "/setup/areas")

    seen_before =
      bridge
      |> ExternalSpaces.list_for_bridge()
      |> Map.new(&{&1.id, &1.last_seen_at})

    view
    |> form("#map-space-#{bridge.id}-garage", %{
      "target_area_id" => Integer.to_string(destination.id)
    })
    |> render_submit()

    seen_after =
      bridge
      |> ExternalSpaces.list_for_bridge()
      |> Map.new(&{&1.id, &1.last_seen_at})

    assert seen_after == seen_before
  end

  test "design refresh failures render their reason and a retry action", %{conn: conn} do
    _bridge = insert_ha_inventory!()

    Application.put_env(
      :hueworks,
      :onboarding_area_design_module,
      __MODULE__.FailedAreaDesign
    )

    {:ok, view, _html} = live(conn, "/setup/areas")

    assert has_element?(view, "[id^='area-design-error-']", "database busy")
    assert has_element?(view, "button[phx-click='retry_design']", "Retry Area design")
    refute has_element?(view, "#area-design-inventory-needed")
  end

  test "the completion action is laid out separately from its wrapping copy", %{conn: conn} do
    bridge = insert_ha_inventory!()
    {:ok, view, _html} = live(conn, "/setup/areas")

    render_submit(view, "use_floor_one", %{
      "bridge_id" => Integer.to_string(bridge.id),
      "external_id" => "floor-1",
      "name" => "Main Floor"
    })

    view
    |> element(
      "#ha-area-#{bridge.id}-garage button[phx-click='skip_space'][phx-value-external_id='garage']"
    )
    |> render_click()

    assert has_element?(
             view,
             "#area-design-complete > .hw-actions > a.hw-button[href='/setup']",
             "Continue setup"
           )
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
      raw_blob: %{"floors" => [], "areas" => [], "config_entries" => []},
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

    bridge
  end

  defmodule FailedAreaDesign do
    def refresh(_bridge), do: {:error, :database_busy}
    def design(_bridge), do: %{progress: %{resolved: 0, total: 0}}
  end
end
