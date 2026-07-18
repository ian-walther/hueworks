defmodule HueworksWeb.BridgeSetupLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    BridgeImport,
    Group,
    GroupLight,
    Light,
    LightState,
    PicoButton,
    PicoDevice,
    Area,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  setup do
    previous = Application.get_env(:hueworks, :import_pipeline)
    previous_payload = Application.get_env(:hueworks, :import_pipeline_payload)
    Application.put_env(:hueworks, :import_pipeline, Hueworks.Import.PipelineStub)

    on_exit(fn ->
      restore_app_env(:hueworks, :import_pipeline, previous)
      restore_app_env(:hueworks, :import_pipeline_payload, previous_payload)
    end)

    :ok
  end

  test "import errors are shown when the import pipeline fails", %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.209",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    Application.delete_env(:hueworks, :import_pipeline_payload)

    {:ok, view, html} = live(conn, "/config/bridges/#{bridge.id}/import")
    refute html =~ "Missing test import payload"

    html = render(view)

    assert html =~ "Missing test import payload"
    assert get_assign(view, :import_status) == :error
    assert get_assign(view, :import_error) == "Missing test import payload"
  end

  test "apply_materialization shows an error when the persisted bridge import is stale", %{
    conn: conn
  } do
    {view, _bridge} = setup_import_view(conn, with_unassigned: false)
    bridge_import = get_assign(view, :bridge_import)
    Repo.delete!(bridge_import)

    html =
      view
      |> element("button[phx-click='apply_materialization']")
      |> render_click()

    assert html =~ "stale"
    assert get_assign(view, :import_status) == :error
  end

  test "successful initial import stays in context with a summary and next actions", %{conn: conn} do
    {view, bridge} = setup_import_view(conn, with_unassigned: false)

    html =
      view
      |> element("button[phx-click='apply_materialization']")
      |> render_click()

    assert html =~ "Import complete"
    assert html =~ "2 lights"
    assert html =~ "2 groups"
    assert has_element?(view, ".hw-summary-stat:first-child strong", "2")
    assert has_element?(view, ".hw-summary-stat:first-child span", "areas created")
    assert html =~ ~s(href="/areas")
    assert html =~ "Review Areas"
    assert html =~ "Create First Scene"
    assert Repo.reload!(bridge).import_complete == true
    refute html =~ "Apply Initial Import"
  end

  test "skipping areas in the UI plan updates the plan state", %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.210",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "area-1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "area-2",
          name: "Kitchen",
          normalized_name: "kitchen",
          metadata: %{}
        }
      ],
      lights: [
        %{
          source: :hue,
          source_id: "1",
          name: "Lamp",
          area_source_id: "area-1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "2",
          name: "Ceiling",
          area_source_id: "area-2",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/import")
    render(view)

    view
    |> form("form[phx-change='set_area_action'][data-area-id='area-1']", %{
      "action" => "skip"
    })
    |> render_change()

    view
    |> form("form[phx-change='set_area_action'][data-area-id='area-2']", %{
      "action" => "skip"
    })
    |> render_change()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:areas, "area-1", "action"]) == "skip"
    assert get_in(plan, [:areas, "area-2", "action"]) == "skip"
  end

  test "area actions normalize numeric source ids", %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.211",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: 12,
          name: "Garage",
          normalized_name: "garage",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/import")
    render(view)

    view
    |> form("form[phx-change='set_area_action'][data-area-id='12']", %{
      "action" => "skip"
    })
    |> render_change()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:areas, "12", "action"]) == "skip"
  end

  test "default area plan merges when names match", %{conn: conn} do
    existing_area =
      Repo.insert!(%Hueworks.Schemas.Area{
        name: "Studio",
        metadata: %{}
      })

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.221",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "area-1",
          name: "Studio",
          normalized_name: "studio",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/import")
    render(view)

    plan = get_assign(view, :plan)

    assert get_in(plan, [:areas, "area-1", "action"]) == "merge"

    assert get_in(plan, [:areas, "area-1", "target_area_id"]) ==
             Integer.to_string(existing_area.id)
  end

  test "native import visibly preselects a full-coverage HA placement suggestion", %{conn: conn} do
    destination = Repo.insert!(%Area{name: "Main Floor"})

    ha_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.251",
        credentials: %{"token" => "token"},
        enabled: true
      })
      |> Repo.insert!()

    {:ok, [ha_space]} =
      Hueworks.ExternalSpaces.sync_bridge_spaces(ha_bridge, [
        %{kind: "ha_area", external_id: "office", name: "Office"}
      ])

    {:ok, _mapping} = Hueworks.ExternalSpaces.put_mapping(ha_space, destination)

    %BridgeImport{}
    |> BridgeImport.changeset(%{
      bridge_id: ha_bridge.id,
      raw_blob: %{},
      normalized_blob: %{
        external_spaces: [],
        areas: [],
        lights: [
          %{
            source_id: "light.office",
            identifiers: %{"mac" => "aa:bb:cc"},
            space_refs: [
              %{kind: "ha_area", external_id: "office", relationship: "direct"}
            ]
          }
        ],
        groups: []
      },
      review_blob: %{},
      status: :normalized,
      imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()

    hue_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.252",
        credentials: %{"api_key" => "key"},
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      external_spaces: [
        %{
          source: :hue,
          source_id: "1",
          kind: "hue_area",
          external_id: "1",
          name: "Office"
        }
      ],
      areas: [
        %{
          source: :hue,
          source_id: "1",
          kind: "hue_area",
          external_id: "1",
          name: "Office",
          normalized_name: "office"
        }
      ],
      lights: [
        %{
          source: :hue,
          source_id: "1",
          name: "Office Lamp",
          area_source_id: "1",
          space_refs: [%{kind: "hue_area", external_id: "1", relationship: "direct"}],
          identifiers: %{"mac" => "aa:bb:cc"},
          capabilities: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{hue_bridge.id}/import")
    html = render(view)

    assert html =~ "Matched through Home Assistant"
    assert html =~ "1 of 1 members agree on Main Floor"

    assert get_in(get_assign(view, :plan), [:areas, "1", "target_area_id"]) ==
             to_string(destination.id)

    view
    |> element("button[phx-click='apply_materialization']")
    |> render_click()

    assert Hueworks.ExternalSpaces.mapped_area_id(hue_bridge, "hue_area", "1") ==
             destination.id
  end

  test "check all preserves merge selection for matching areas", %{conn: conn} do
    existing_area =
      Repo.insert!(%Hueworks.Schemas.Area{
        name: "Studio",
        metadata: %{}
      })

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.222",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "area-1",
          name: "Studio",
          normalized_name: "studio",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/import")
    render(view)

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='check']")
    |> render_click()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:areas, "area-1", "action"]) == "merge"

    assert get_in(plan, [:areas, "area-1", "target_area_id"]) ==
             Integer.to_string(existing_area.id)
  end

  test "merge dropdown selects matching area by default", %{conn: conn} do
    existing_area =
      Repo.insert!(%Hueworks.Schemas.Area{
        name: "Studio",
        metadata: %{}
      })

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.223",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "area-1",
          name: "Studio",
          normalized_name: "studio",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/import")
    render(view)

    selected =
      view
      |> element("form[phx-change='set_area_merge'][data-area-id='area-1'] option[selected]")
      |> render()

    assert selected =~ "value=\"#{existing_area.id}\""
  end

  test "merge dropdown shows area display_name when present", %{conn: conn} do
    _existing_area =
      Repo.insert!(%Hueworks.Schemas.Area{
        name: "Studio",
        display_name: "Studio Upstairs",
        metadata: %{}
      })

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.224",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "area-1",
          name: "Studio",
          normalized_name: "studio",
          metadata: %{}
        }
      ],
      lights: [],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/import")
    html = render(view)

    assert html =~ "Studio Upstairs"
    refute html =~ ">Studio</option>"
  end

  test "ignores late z2m snapshot messages without crashing", %{conn: conn} do
    {view, _bridge} = setup_import_view(conn, with_unassigned: false)
    ref = Process.monitor(view.pid)

    send(view.pid, {:z2m_message, "zigbee2mqtt/bridge/info", ~s({"version":"1.0.0"})})
    send(view.pid, {:z2m_connection, :down})

    assert render(view) =~ "Configuration loaded into memory"
    refute_received {:DOWN, ^ref, :process, _pid, _reason}
  end

  test "light and group checkboxes toggle plan selections", %{conn: conn} do
    {view, _bridge} = setup_import_view(conn, with_unassigned: true)

    view
    |> element("input[phx-click='toggle_light'][phx-value-id='light-1']")
    |> render_click()

    view
    |> element("input[phx-click='toggle_group'][phx-value-id='group-1']")
    |> render_click()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:lights, "light-1"]) == false
    assert get_in(plan, [:groups, "group-1"]) == false
  end

  test "check all buttons update areas, lights, and groups at every level", %{conn: conn} do
    {view, _bridge} = setup_import_view(conn, with_unassigned: true)

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='uncheck']")
    |> render_click()

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='check']")
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area'][phx-value-area_id='area-1'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='area-2'][phx-value-section='lights'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='area-2'][phx-value-section='groups'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='unassigned'][phx-value-section='lights'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='unassigned'][phx-value-section='groups'][phx-value-action='check']"
    )
    |> render_click()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:areas, "area-1", "action"]) == "create"
    assert get_in(plan, [:areas, "area-2", "action"]) == "create"

    assert get_in(plan, [:lights, "light-1"]) == true
    assert get_in(plan, [:lights, "light-2"]) == true
    assert get_in(plan, [:lights, "light-3"]) == true

    assert get_in(plan, [:groups, "group-1"]) == true
    assert get_in(plan, [:groups, "group-2"]) == true
    assert get_in(plan, [:groups, "group-3"]) == true
  end

  test "uncheck all buttons update areas, lights, and groups at every level", %{conn: conn} do
    {view, _bridge} = setup_import_view(conn, with_unassigned: true)

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='uncheck']")
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area'][phx-value-area_id='area-1'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='area-2'][phx-value-section='lights'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='area-2'][phx-value-section='groups'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='unassigned'][phx-value-section='lights'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_area_section'][phx-value-area_id='unassigned'][phx-value-section='groups'][phx-value-action='uncheck']"
    )
    |> render_click()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:areas, "area-1", "action"]) == "skip"
    assert get_in(plan, [:areas, "area-2", "action"]) == "skip"

    assert get_in(plan, [:lights, "light-1"]) == false
    assert get_in(plan, [:lights, "light-2"]) == false
    assert get_in(plan, [:lights, "light-3"]) == false

    assert get_in(plan, [:groups, "group-1"]) == false
    assert get_in(plan, [:groups, "group-2"]) == false
    assert get_in(plan, [:groups, "group-3"]) == false
  end

  test "unassigned entity area dropdown stores target area in plan", %{conn: conn} do
    existing_area =
      Repo.insert!(%Hueworks.Schemas.Area{
        name: "Patio",
        metadata: %{}
      })

    {view, _bridge} = setup_import_view(conn, with_unassigned: true)

    view
    |> form("form[phx-change='set_entity_area'][data-type='lights'][data-source-id='light-3']", %{
      "type" => "lights",
      "source_id" => "light-3",
      "target_area_id" => Integer.to_string(existing_area.id)
    })
    |> render_change()

    view
    |> form("form[phx-change='set_entity_area'][data-type='groups'][data-source-id='group-3']", %{
      "type" => "groups",
      "source_id" => "group-3",
      "target_area_id" => Integer.to_string(existing_area.id)
    })
    |> render_change()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:lights, "light-3", "target_area_id"]) ==
             Integer.to_string(existing_area.id)

    assert get_in(plan, [:groups, "group-3", "target_area_id"]) ==
             Integer.to_string(existing_area.id)
  end

  test "reimport makes importing and creating an unmatched bridge area explicit", %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.230",
        credentials: %{"api_key" => "key"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "bridge-office",
          name: "Bridge Office",
          normalized_name: "bridge office",
          metadata: %{}
        }
      ],
      lights: [
        %{
          source: :hue,
          source_id: "new-light",
          name: "New Lamp",
          area_source_id: "bridge-office",
          capabilities: %{},
          identifiers: %{},
          metadata: %{"uniqueid" => "new-light-uid"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/reimport")
    render(view)

    assert get_in(get_assign(view, :plan), [:lights, "new-light"]) == %{
             "resolution" => "do_not_import",
             "selected" => false,
             "target_area_id" => "unassigned"
           }

    assert get_in(get_assign(view, :plan), [:areas, "bridge-office", "action"]) == "skip"

    refute has_element?(
             view,
             "form[phx-change='set_entity_area'][data-source-id='new-light']"
           )

    view
    |> form(
      "form[phx-change='set_entity_resolution'][data-source-id='new-light']",
      %{
        "type" => "lights",
        "source_id" => "new-light",
        "resolution" => "import"
      }
    )
    |> render_change()

    assert has_element?(
             view,
             "form[phx-change='set_entity_area'][data-source-id='new-light'] option[value='unassigned']",
             "Unassigned"
           )

    assert has_element?(
             view,
             "form[phx-change='set_entity_area'][data-source-id='new-light'] option[value='bridge_area:bridge-office']",
             ~s(Create "Bridge Office")
           )

    view
    |> form("form[phx-change='set_entity_area'][data-source-id='new-light']", %{
      "type" => "lights",
      "source_id" => "new-light",
      "target_area_id" => "bridge_area:bridge-office"
    })
    |> render_change()

    assert get_in(get_assign(view, :plan), [:lights, "new-light", "target_area_id"]) ==
             "bridge_area"

    assert get_in(get_assign(view, :plan), [:areas, "bridge-office", "action"]) == "create"

    view
    |> form(
      "form[phx-change='set_entity_resolution'][data-source-id='new-light']",
      %{
        "type" => "lights",
        "source_id" => "new-light",
        "resolution" => "do_not_import"
      }
    )
    |> render_change()

    assert get_in(get_assign(view, :plan), [:areas, "bridge-office", "action"]) == "skip"
  end

  test "initial import and reimport render independent workflows", %{conn: conn} do
    initial_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "New Hue Bridge",
        host: "10.0.0.229",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    Application.put_env(:hueworks, :import_pipeline_payload, %{
      areas: [],
      lights: [],
      groups: [],
      memberships: %{}
    })

    {:ok, initial_view, _html} = live(conn, "/config/bridges/#{initial_bridge.id}/import")
    render(initial_view)

    assert has_element?(initial_view, "#initial-import-review")
    refute has_element?(initial_view, "#removed-from-bridge")

    Repo.update!(Bridge.changeset(initial_bridge, %{import_complete: true}))

    {:ok, reimport_view, _html} = live(conn, "/config/bridges/#{initial_bridge.id}/reimport")
    render(reimport_view)

    assert has_element?(reimport_view, "section[aria-label='Reimport summary']")
    assert has_element?(reimport_view, ".hw-state-message-success")
    assert has_element?(reimport_view, "a[href='/config/bridges']", "Return to Bridges")
    refute has_element?(reimport_view, "#apply-reimport")
    refute has_element?(reimport_view, "#initial-import-review")
    refute has_element?(reimport_view, "form[phx-change='set_area_action']")
    refute has_element?(reimport_view, "#removed-from-bridge")
  end

  test "applied reimport stays in context with a transaction receipt", %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.230",
        credentials: %{"api_key" => "key"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    light =
      %Light{}
      |> Light.changeset(%{
        name: "Old bridge name",
        source: :hue,
        source_id: "light-1",
        bridge_id: bridge.id,
        metadata: %{},
        normalized_json: %{
          "source" => "hue",
          "source_id" => "light-1",
          "name" => "Old bridge name",
          "capabilities" => %{}
        }
      })
      |> Repo.insert!()

    Application.put_env(:hueworks, :import_pipeline_payload, %{
      areas: [],
      lights: [
        %{
          source: :hue,
          source_id: "light-1",
          name: "New bridge name",
          area_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    })

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/reimport")
    render(view)

    assert has_element?(view, "#apply-reimport")
    render_click(element(view, "#apply-reimport"))

    assert has_element?(view, "#reimport-complete")
    assert has_element?(view, "[aria-label='Applied bridge changes']")
    assert has_element?(view, "a[href='/config/bridges']", "Return to Bridges")
    assert has_element?(view, "button[phx-click='import_configuration']", "Review Again")
    assert Repo.get!(Light, light.id).name == "New bridge name"
  end

  test "default reimport apply preserves an existing HA light left unlinked", %{conn: conn} do
    hue_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.231",
        credentials: %{"api_key" => "key"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    _hue_light =
      %Light{}
      |> Light.changeset(%{
        name: "Hue Lamp",
        source: :hue,
        source_id: "1",
        bridge_id: hue_bridge.id,
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })
      |> Repo.insert!()

    ha_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.232",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    ha_light =
      %Light{}
      |> Light.changeset(%{
        name: "HA Lamp",
        source: :ha,
        source_id: "light.hue_lamp",
        bridge_id: ha_bridge.id,
        canonical_light_id: nil,
        metadata: %{},
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.hue_lamp",
          "metadata" => %{"entity_id" => "light.hue_lamp"}
        }
      })
      |> Repo.insert!()

    normalized = %{
      areas: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "HA Lamp",
          area_source_id: nil,
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"entity_id" => "light.hue_lamp"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{ha_bridge.id}/reimport")
    render(view)

    view
    |> element("button[phx-click='apply_reimport']")
    |> render_click()

    assert Repo.get!(Light, ha_light.id).canonical_light_id == nil
  end

  test "default reimport apply preserves an existing HA group left unlinked", %{conn: conn} do
    hue_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.233",
        credentials: %{"api_key" => "key"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    hue_light =
      %Light{}
      |> Light.changeset(%{
        name: "Hue Lamp",
        source: :hue,
        source_id: "1",
        bridge_id: hue_bridge.id,
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })
      |> Repo.insert!()

    hue_group =
      %Group{}
      |> Group.changeset(%{
        name: "Hue Group",
        source: :hue,
        source_id: "group-1",
        bridge_id: hue_bridge.id
      })
      |> Repo.insert!()

    Repo.insert!(%GroupLight{group_id: hue_group.id, light_id: hue_light.id})

    ha_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.234",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    ha_light =
      %Light{}
      |> Light.changeset(%{
        name: "HA Lamp",
        source: :ha,
        source_id: "light.hue_lamp",
        bridge_id: ha_bridge.id,
        canonical_light_id: hue_light.id,
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}},
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.hue_lamp",
          "metadata" => %{"entity_id" => "light.hue_lamp"}
        }
      })
      |> Repo.insert!()

    ha_group =
      %Group{}
      |> Group.changeset(%{
        name: "HA Group",
        source: :ha,
        source_id: "group.hue",
        bridge_id: ha_bridge.id,
        canonical_group_id: nil,
        normalized_json: %{
          "source" => "ha",
          "source_id" => "group.hue",
          "metadata" => %{"entity_id" => "group.hue"}
        }
      })
      |> Repo.insert!()

    Repo.insert!(%GroupLight{group_id: ha_group.id, light_id: ha_light.id})

    normalized = %{
      areas: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "HA Lamp",
          area_source_id: nil,
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"entity_id" => "light.hue_lamp"}
        }
      ],
      groups: [
        %{
          source: :ha,
          source_id: "group.hue",
          name: "HA Group",
          area_source_id: nil,
          type: "group",
          capabilities: %{},
          metadata: %{"entity_id" => "group.hue"}
        }
      ],
      memberships: %{
        group_lights: [
          %{group_source_id: "group.hue", light_source_id: "light.hue_lamp"}
        ]
      }
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{ha_bridge.id}/reimport")
    render(view)

    view
    |> element("button[phx-click='apply_reimport']")
    |> render_click()

    assert Repo.get!(Group, ha_group.id).canonical_group_id == nil
  end

  test "reimport duplicate resolution can be changed to import as real from the review UI", %{
    conn: conn
  } do
    hue_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.241",
        credentials: %{"api_key" => "key"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    %Light{}
    |> Light.changeset(%{
      name: "Hue Lamp",
      source: :hue,
      source_id: "1",
      bridge_id: hue_bridge.id,
      metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
    })
    |> Repo.insert!()

    ha_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.242",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [],
      lights: [
        %{
          source: :ha,
          source_id: "light.hue_lamp",
          name: "HA Lamp",
          area_source_id: nil,
          capabilities: %{},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"unique_id" => "ha-hue-lamp"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{ha_bridge.id}/reimport")
    render(view)

    view
    |> form(
      "form[phx-change='set_entity_resolution'][data-type='lights'][data-source-id='light.hue_lamp']",
      %{
        "type" => "lights",
        "source_id" => "light.hue_lamp",
        "resolution" => "import_real"
      }
    )
    |> render_change()

    assert get_in(get_assign(view, :plan), [
             :lights,
             "light.hue_lamp",
             "resolution"
           ]) == "import_real"
  end

  test "reimport missing entity resolution can disable an existing entity from the review UI", %{
    conn: conn
  } do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.243",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    light =
      %Light{}
      |> Light.changeset(%{
        name: "Missing Light",
        source: :ha,
        source_id: "light.missing",
        bridge_id: bridge.id,
        external_id: "light.missing",
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.missing",
          "name" => "Missing Light",
          "metadata" => %{"entity_id" => "light.missing"}
        }
      })
      |> Repo.insert!()

    Application.put_env(:hueworks, :import_pipeline_payload, %{
      areas: [],
      lights: [],
      groups: [],
      memberships: %{}
    })

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/reimport")
    render(view)

    view
    |> form(
      "form[phx-change='set_entity_resolution'][data-type='lights'][data-source-id='light.missing']",
      %{
        "type" => "lights",
        "source_id" => "light.missing",
        "resolution" => "disable"
      }
    )
    |> render_change()

    view
    |> element("button[phx-click='apply_reimport']")
    |> render_click()

    view
    |> element("button[phx-click='apply_reimport'][phx-value-confirmed='true']")
    |> render_click()

    refute Repo.reload!(light).enabled
  end

  test "destructive reimport resolutions show dependent scene and group references before applying",
       %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.245",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    area = Repo.insert!(%Area{name: "Office"})

    light =
      %Light{}
      |> Light.changeset(%{
        name: "Missing Light",
        source: :ha,
        source_id: "light.missing",
        bridge_id: bridge.id,
        area_id: area.id,
        external_id: "light.missing",
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.missing",
          "name" => "Missing Light",
          "metadata" => %{"entity_id" => "light.missing"}
        }
      })
      |> Repo.insert!()

    group =
      %Group{}
      |> Group.changeset(%{
        name: "Existing Group",
        source: :ha,
        source_id: "group.existing",
        bridge_id: bridge.id,
        area_id: area.id
      })
      |> Repo.insert!()

    group_light = Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    scene = Repo.insert!(%Scene{name: "Existing Scene", area_id: area.id})
    light_state = Repo.insert!(%LightState{name: "Existing State", type: :manual})
    component = Repo.insert!(%SceneComponent{scene_id: scene.id, light_state_id: light_state.id})

    scene_component_light =
      Repo.insert!(%SceneComponentLight{scene_component_id: component.id, light_id: light.id})

    Application.put_env(:hueworks, :import_pipeline_payload, %{
      areas: [],
      lights: [],
      groups: [],
      memberships: %{}
    })

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/reimport")
    render(view)

    view
    |> form(
      "form[phx-change='set_entity_resolution'][data-type='lights'][data-source-id='light.missing']",
      %{
        "type" => "lights",
        "source_id" => "light.missing",
        "resolution" => "delete"
      }
    )
    |> render_change()

    html =
      view
      |> element("button[phx-click='apply_reimport']")
      |> render_click()

    assert html =~ "Confirm destructive bridge changes"
    assert html =~ "Missing Light"
    assert html =~ "Delete"
    assert html =~ "Existing Scene"
    assert html =~ "Existing Group"
    assert Repo.get(Light, light.id)
    assert Repo.get(SceneComponentLight, scene_component_light.id)
    assert Repo.get(GroupLight, group_light.id)

    view
    |> element("button[phx-click='apply_reimport'][phx-value-confirmed='true']")
    |> render_click()

    refute Repo.get(Light, light.id)
    refute Repo.get(SceneComponentLight, scene_component_light.id)
    refute Repo.get(GroupLight, group_light.id)
  end

  test "stale reimport resolution errors refresh the review with a human message", %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.244",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    light =
      %Light{}
      |> Light.changeset(%{
        name: "Missing Light",
        source: :ha,
        source_id: "light.missing",
        bridge_id: bridge.id,
        external_id: "light.missing",
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.missing",
          "name" => "Missing Light",
          "metadata" => %{"entity_id" => "light.missing"}
        }
      })
      |> Repo.insert!()

    Application.put_env(:hueworks, :import_pipeline_payload, %{
      areas: [],
      lights: [],
      groups: [],
      memberships: %{}
    })

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/reimport")
    render(view)

    view
    |> form(
      "form[phx-change='set_entity_resolution'][data-type='lights'][data-source-id='light.missing']",
      %{
        "type" => "lights",
        "source_id" => "light.missing",
        "resolution" => "disable"
      }
    )
    |> render_change()

    light
    |> Ecto.Changeset.change(
      external_id: "changed-after-review",
      normalized_json: %{
        "source" => "ha",
        "source_id" => "light.missing",
        "name" => "Missing Light",
        "metadata" => %{"entity_id" => "changed-after-review"}
      }
    )
    |> Repo.update!()

    view
    |> element("button[phx-click='apply_reimport']")
    |> render_click()

    html =
      view
      |> element("button[phx-click='apply_reimport'][phx-value-confirmed='true']")
      |> render_click()

    assert html =~ "review is out of date"
    refute html =~ "{:stale_resolution"
    assert get_assign(view, :import_error) =~ "review is out of date"

    assert get_in(get_assign(view, :plan), [
             :lights,
             "light.missing",
             "expected_external_id"
           ]) == "changed-after-review"
  end

  test "default reimport apply preserves existing entities and scene references when upstream omits them",
       %{conn: conn} do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.235",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    area = Repo.insert!(%Area{name: "Existing Area"})

    light =
      %Light{}
      |> Light.changeset(%{
        name: "Existing Light",
        source: :ha,
        source_id: "light.existing",
        bridge_id: bridge.id,
        area_id: area.id,
        external_id: "light.existing",
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.existing",
          "metadata" => %{"entity_id" => "light.existing"}
        }
      })
      |> Repo.insert!()

    group =
      %Group{}
      |> Group.changeset(%{
        name: "Existing Group",
        source: :ha,
        source_id: "group.existing",
        bridge_id: bridge.id,
        area_id: area.id,
        external_id: "group.existing",
        normalized_json: %{
          "source" => "ha",
          "source_id" => "group.existing",
          "metadata" => %{"entity_id" => "group.existing"}
        }
      })
      |> Repo.insert!()

    group_light = Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    scene = Repo.insert!(%Scene{name: "Existing Scene", area_id: area.id})
    light_state = Repo.insert!(%LightState{name: "Existing State", type: :manual})
    component = Repo.insert!(%SceneComponent{scene_id: scene.id, light_state_id: light_state.id})

    scene_component_light =
      Repo.insert!(%SceneComponentLight{scene_component_id: component.id, light_id: light.id})

    normalized = %{areas: [], lights: [], groups: [], memberships: %{}}
    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/reimport")
    render(view)

    view
    |> element("button[phx-click='apply_reimport']")
    |> render_click()

    assert Repo.get(Light, light.id)
    assert Repo.get(Group, group.id)
    assert Repo.get(GroupLight, group_light.id)
    assert Repo.get(SceneComponentLight, scene_component_light.id)
  end

  test "default reimport apply on a caseta bridge preserves pico devices and buttons", %{
    conn: conn
  } do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :caseta,
        name: "Caseta Bridge",
        host: "10.0.0.236",
        credentials: %{"cert_path" => "cert.pem", "key_path" => "key.pem"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    _light =
      %Light{}
      |> Light.changeset(%{
        name: "Caseta Lamp",
        source: :caseta,
        source_id: "zone-1",
        bridge_id: bridge.id,
        external_id: "caseta-device-1",
        metadata: %{"device_id" => "caseta-device-1"},
        normalized_json: %{
          "source" => "caseta",
          "source_id" => "zone-1",
          "metadata" => %{"device_id" => "caseta-device-1"}
        }
      })
      |> Repo.insert!()

    pico_device =
      %PicoDevice{}
      |> PicoDevice.changeset(%{
        bridge_id: bridge.id,
        source_id: "pico-1",
        name: "Bedside Pico",
        display_name: "Custom Pico Name",
        hardware_profile: "pico_3brl",
        enabled: true,
        metadata: %{"area_override" => true}
      })
      |> Repo.insert!()

    pico_button =
      %PicoButton{}
      |> PicoButton.changeset(%{
        pico_device_id: pico_device.id,
        source_id: "button-1",
        button_number: 2,
        slot_index: 0,
        action_type: "scene"
      })
      |> Repo.insert!()

    normalized = %{
      areas: [],
      lights: [
        %{
          source: :caseta,
          source_id: "zone-1",
          name: "Caseta Lamp",
          area_source_id: nil,
          capabilities: %{},
          identifiers: %{},
          metadata: %{"device_id" => "caseta-device-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/reimport")
    render(view)

    view
    |> element("button[phx-click='apply_reimport']")
    |> render_click()

    assert Repo.get(PicoDevice, pico_device.id)
    assert Repo.get(PicoButton, pico_button.id)
  end

  test "default reimport apply of a hue bridge does not relink HA lights on other bridges", %{
    conn: conn
  } do
    hue_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.237",
        credentials: %{"api_key" => "key"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    _hue_light =
      %Light{}
      |> Light.changeset(%{
        name: "Hue Lamp",
        source: :hue,
        source_id: "1",
        bridge_id: hue_bridge.id,
        external_id: "aa:bb:cc-1",
        metadata: %{"uniqueid" => "aa:bb:cc-1", "identifiers" => %{"mac" => "aa:bb:cc"}},
        normalized_json: %{
          "source" => "hue",
          "source_id" => "1",
          "identifiers" => %{"mac" => "aa:bb:cc"},
          "metadata" => %{"uniqueid" => "aa:bb:cc-1"}
        }
      })
      |> Repo.insert!()

    ha_bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.238",
        credentials: %{"token" => "token"},
        import_complete: true,
        enabled: true
      })
      |> Repo.insert!()

    ha_light =
      %Light{}
      |> Light.changeset(%{
        name: "HA Lamp",
        source: :ha,
        source_id: "light.hue_lamp",
        bridge_id: ha_bridge.id,
        canonical_light_id: nil,
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}},
        normalized_json: %{
          "source" => "ha",
          "source_id" => "light.hue_lamp",
          "metadata" => %{"entity_id" => "light.hue_lamp"}
        }
      })
      |> Repo.insert!()

    normalized = %{
      areas: [],
      lights: [
        %{
          source: :hue,
          source_id: "1",
          name: "Hue Lamp",
          area_source_id: nil,
          capabilities: %{color: true},
          identifiers: %{"mac" => "aa:bb:cc"},
          metadata: %{"uniqueid" => "aa:bb:cc-1"}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{hue_bridge.id}/reimport")
    render(view)

    view
    |> element("button[phx-click='apply_reimport']")
    |> render_click()

    assert Repo.get!(Light, ha_light.id).canonical_light_id == nil
  end

  defp setup_import_view(conn, opts) do
    with_unassigned = Keyword.get(opts, :with_unassigned, false)

    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.212",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = %{
      areas: [
        %{
          source: :hue,
          source_id: "area-1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "area-2",
          name: "Kitchen",
          normalized_name: "kitchen",
          metadata: %{}
        }
      ],
      lights: [
        %{
          source: :hue,
          source_id: "light-1",
          name: "Desk Lamp",
          area_source_id: "area-1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "light-2",
          name: "Island",
          area_source_id: "area-2",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [
        %{
          source: :hue,
          source_id: "group-1",
          name: "Office Group",
          area_source_id: "area-1",
          type: "area",
          capabilities: %{},
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "group-2",
          name: "Kitchen Group",
          area_source_id: "area-2",
          type: "area",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{}
    }

    normalized =
      if with_unassigned do
        %{
          normalized
          | lights: normalized.lights ++ [unassigned_light()],
            groups: normalized.groups ++ [unassigned_group()]
        }
      else
        normalized
      end

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridges/#{bridge.id}/import")
    render(view)

    {view, bridge}
  end

  defp unassigned_light do
    %{
      source: :hue,
      source_id: "light-3",
      name: "Porch",
      area_source_id: nil,
      capabilities: %{},
      identifiers: %{},
      metadata: %{}
    }
  end

  defp unassigned_group do
    %{
      source: :hue,
      source_id: "group-3",
      name: "Outdoor Group",
      area_source_id: nil,
      type: "zone",
      capabilities: %{},
      metadata: %{}
    }
  end

  defp get_assign(view, key) do
    %{socket: %Phoenix.LiveView.Socket{assigns: assigns}} = :sys.get_state(view.pid)
    Map.get(assigns, key)
  end
end

defmodule Hueworks.Import.PipelineStub do
  alias Hueworks.Import.Plan
  alias Hueworks.Repo
  alias Hueworks.Schemas.BridgeImport

  def create_import(bridge) do
    normalized = Application.get_env(:hueworks, :import_pipeline_payload)

    if is_map(normalized) do
      plan = Plan.build_default(normalized)

      {:ok, bridge_import} =
        %BridgeImport{}
        |> BridgeImport.changeset(%{
          bridge_id: bridge.id,
          raw_blob: %{},
          normalized_blob: normalized,
          review_blob: plan,
          status: :normalized,
          imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      {:ok, bridge_import}
    else
      {:error, "Missing test import payload"}
    end
  end
end
