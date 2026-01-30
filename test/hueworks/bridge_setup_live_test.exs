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
