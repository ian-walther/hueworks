defmodule HueworksWeb.BridgeSetupLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, BridgeImport}

  setup do
    previous = Application.get_env(:hueworks, :import_pipeline)
    Application.put_env(:hueworks, :import_pipeline, Hueworks.Import.PipelineStub)

    on_exit(fn ->
      Application.put_env(:hueworks, :import_pipeline, previous)
      Application.delete_env(:hueworks, :import_pipeline_payload)
    end)

    :ok
  end

  test "skipping rooms in the UI plan updates the plan state", %{conn: conn} do
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
      rooms: [
        %{
          source: :hue,
          source_id: "room-1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "room-2",
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
          room_source_id: "room-1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "2",
          name: "Ceiling",
          room_source_id: "room-2",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        }
      ],
      groups: [],
      memberships: %{}
    }

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/setup")
    render(view)

    view
    |> form("form[phx-change='set_room_action'][data-room-id='room-1']", %{
      "action" => "skip"
    })
    |> render_change()

    view
    |> form("form[phx-change='set_room_action'][data-room-id='room-2']", %{
      "action" => "skip"
    })
    |> render_change()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:rooms, "room-1", "action"]) == "skip"
    assert get_in(plan, [:rooms, "room-2", "action"]) == "skip"
  end

  test "room actions normalize numeric source ids", %{conn: conn} do
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
      rooms: [
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

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/setup")
    render(view)
    view
    |> form("form[phx-change='set_room_action'][data-room-id='12']", %{
      "action" => "skip"
    })
    |> render_change()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:rooms, "12", "action"]) == "skip"
  end

  test "default room plan merges when names match", %{conn: conn} do
    existing_room =
      Repo.insert!(%Hueworks.Schemas.Room{
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
      rooms: [
        %{
          source: :hue,
          source_id: "room-1",
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

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/setup")
    render(view)

    plan = get_assign(view, :plan)

    assert get_in(plan, [:rooms, "room-1", "action"]) == "merge"
    assert get_in(plan, [:rooms, "room-1", "target_room_id"]) ==
             Integer.to_string(existing_room.id)
  end

  test "check all preserves merge selection for matching rooms", %{conn: conn} do
    existing_room =
      Repo.insert!(%Hueworks.Schemas.Room{
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
      rooms: [
        %{
          source: :hue,
          source_id: "room-1",
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

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/setup")
    render(view)

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='check']")
    |> render_click()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:rooms, "room-1", "action"]) == "merge"
    assert get_in(plan, [:rooms, "room-1", "target_room_id"]) ==
             Integer.to_string(existing_room.id)
  end

  test "merge dropdown selects matching room by default", %{conn: conn} do
    existing_room =
      Repo.insert!(%Hueworks.Schemas.Room{
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
      rooms: [
        %{
          source: :hue,
          source_id: "room-1",
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

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/setup")
    render(view)

    selected =
      view
      |> element("form[phx-change='set_room_merge'][data-room-id='room-1'] option[selected]")
      |> render()

    assert selected =~ "value=\"#{existing_room.id}\""
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

  test "check all buttons update rooms, lights, and groups at every level", %{conn: conn} do
    {view, _bridge} = setup_import_view(conn, with_unassigned: true)

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='uncheck']")
    |> render_click()

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='check']")
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room'][phx-value-room_id='room-1'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='room-2'][phx-value-section='lights'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='room-2'][phx-value-section='groups'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='unassigned'][phx-value-section='lights'][phx-value-action='check']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='unassigned'][phx-value-section='groups'][phx-value-action='check']"
    )
    |> render_click()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:rooms, "room-1", "action"]) == "create"
    assert get_in(plan, [:rooms, "room-2", "action"]) == "create"

    assert get_in(plan, [:lights, "light-1"]) == true
    assert get_in(plan, [:lights, "light-2"]) == true
    assert get_in(plan, [:lights, "light-3"]) == true

    assert get_in(plan, [:groups, "group-1"]) == true
    assert get_in(plan, [:groups, "group-2"]) == true
    assert get_in(plan, [:groups, "group-3"]) == true
  end

  test "uncheck all buttons update rooms, lights, and groups at every level", %{conn: conn} do
    {view, _bridge} = setup_import_view(conn, with_unassigned: true)

    view
    |> element("button[phx-click='toggle_all'][phx-value-action='uncheck']")
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room'][phx-value-room_id='room-1'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='room-2'][phx-value-section='lights'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='room-2'][phx-value-section='groups'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='unassigned'][phx-value-section='lights'][phx-value-action='uncheck']"
    )
    |> render_click()

    view
    |> element(
      "button[phx-click='toggle_room_section'][phx-value-room_id='unassigned'][phx-value-section='groups'][phx-value-action='uncheck']"
    )
    |> render_click()

    plan = get_assign(view, :plan)

    assert get_in(plan, [:rooms, "room-1", "action"]) == "skip"
    assert get_in(plan, [:rooms, "room-2", "action"]) == "skip"

    assert get_in(plan, [:lights, "light-1"]) == false
    assert get_in(plan, [:lights, "light-2"]) == false
    assert get_in(plan, [:lights, "light-3"]) == false

    assert get_in(plan, [:groups, "group-1"]) == false
    assert get_in(plan, [:groups, "group-2"]) == false
    assert get_in(plan, [:groups, "group-3"]) == false
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
      rooms: [
        %{
          source: :hue,
          source_id: "room-1",
          name: "Office",
          normalized_name: "office",
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "room-2",
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
          room_source_id: "room-1",
          capabilities: %{},
          identifiers: %{},
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "light-2",
          name: "Island",
          room_source_id: "room-2",
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
          room_source_id: "room-1",
          type: "room",
          capabilities: %{},
          metadata: %{}
        },
        %{
          source: :hue,
          source_id: "group-2",
          name: "Kitchen Group",
          room_source_id: "room-2",
          type: "room",
          capabilities: %{},
          metadata: %{}
        }
      ],
      memberships: %{}
    }

    normalized =
      if with_unassigned do
        %{normalized | lights: normalized.lights ++ [unassigned_light()], groups: normalized.groups ++ [unassigned_group()]}
      else
        normalized
      end

    Application.put_env(:hueworks, :import_pipeline_payload, normalized)

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/setup")
    render(view)

    {view, bridge}
  end

  defp unassigned_light do
    %{
      source: :hue,
      source_id: "light-3",
      name: "Porch",
      room_source_id: nil,
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
      room_source_id: nil,
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
