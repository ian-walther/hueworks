defmodule HueworksWeb.PicoConfigLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, PicoButton, PicoDevice, Room}

  defmodule CasetaPicoFetcherStub do
    def fetch_for_bridge(_bridge) do
      %{
        lights: [
          %{zone_id: "42", area_id: "100", name: "Main Floor / Overhead"}
        ],
        pico_buttons: [
          %{
            button_id: "1",
            button_number: 2,
            parent_device_id: "device-1",
            device_name: "Main Floor Pico",
            area_id: "100"
          },
          %{
            button_id: "2",
            button_number: 3,
            parent_device_id: "device-1",
            device_name: "Main Floor Pico",
            area_id: "100"
          },
          %{
            button_id: "3",
            button_number: 4,
            parent_device_id: "device-1",
            device_name: "Main Floor Pico",
            area_id: "100"
          },
          %{
            button_id: "4",
            button_number: 5,
            parent_device_id: "device-1",
            device_name: "Main Floor Pico",
            area_id: "100"
          },
          %{
            button_id: "5",
            button_number: 6,
            parent_device_id: "device-1",
            device_name: "Main Floor Pico",
            area_id: "100"
          }
        ]
      }
    end
  end

  setup do
    previous = Application.get_env(:hueworks, :caseta_pico_fetcher)
    Application.put_env(:hueworks, :caseta_pico_fetcher, CasetaPicoFetcherStub)

    on_exit(fn ->
      if previous do
        Application.put_env(:hueworks, :caseta_pico_fetcher, previous)
      else
        Application.delete_env(:hueworks, :caseta_pico_fetcher)
      end
    end)

    :ok
  end

  test "config page shows Pico Config button for Caseta bridges", %{conn: conn} do
    Repo.insert!(%Bridge{
      type: :caseta,
      name: "Caseta",
      host: "10.0.0.60",
      credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
      enabled: true,
      import_complete: true
    })

    Repo.insert!(%Bridge{
      type: :hue,
      name: "Hue",
      host: "10.0.0.61",
      credentials: %{"api_key" => "key"},
      enabled: true,
      import_complete: true
    })

    {:ok, _view, html} = live(conn, "/config")

    assert html =~ "/config/bridge/"
    assert html =~ "Pico Config"
  end

  test "pico config creates control groups and assigns buttons by press", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Main Floor"})
    override_room = Repo.insert!(%Room{name: "Override Room"})

    bridge =
      Repo.insert!(%Bridge{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.62",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    overhead =
      Repo.insert!(%Light{
        name: "Overhead",
        source: :caseta,
        source_id: "42",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    _lamp =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "43",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    override_overhead =
      Repo.insert!(%Light{
        name: "Override Overhead",
        source: :caseta,
        source_id: "44",
        bridge_id: bridge.id,
        room_id: override_room.id,
        enabled: true
      })

    _override_lamp =
      Repo.insert!(%Light{
        name: "Override Lamp",
        source: :caseta,
        source_id: "45",
        bridge_id: bridge.id,
        room_id: override_room.id,
        enabled: true
      })

    group =
      Repo.insert!(%Group{
        name: "Overhead Group",
        source: :caseta,
        source_id: "group-1",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: overhead.id})

    override_group =
      Repo.insert!(%Group{
        name: "Override Overhead Group",
        source: :caseta,
        source_id: "group-2",
        bridge_id: bridge.id,
        room_id: override_room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: override_group.id, light_id: override_overhead.id})

    {:ok, view, html} = live(conn, "/config/bridge/#{bridge.id}/picos")
    assert html =~ "No Picos synced yet."

    render_click(element(view, "button[phx-click='sync_picos']"))

    html = render(view)
    assert html =~ "Main Floor Pico"
    assert html =~ "Control Groups"
    assert html =~ "Using auto-detected room from Caseta import data."

    view
    |> form("form[phx-submit='save_room_override']", %{
      "room_id" => Integer.to_string(override_room.id)
    })
    |> render_submit()

    assert render(view) =~ "Pico room updated."
    assert render(view) =~ "Using manual room override."

    view
    |> form("#pico-new-control-group-form", %{"name" => "Overhead"})
    |> render_submit()

    assert render(view) =~ "Control group created."

    view
    |> form("#pico-control-group-group-form", %{
      "entity" => "group",
      "id" => Integer.to_string(override_group.id)
    })
    |> render_change()

    render_click(element(view, "#pico-add-control-group-group"))
    render_click(element(view, "#pico-save-control-group"))

    assert render(view) =~ "Control group saved."

    device = Repo.one!(PicoDevice)
    [control_group] = Picos.control_groups(device)

    view
    |> form("#pico-binding-editor-form", %{
      "target_kind" => "control_group",
      "action" => "toggle"
    })
    |> render_change()

    view
    |> form("#pico-binding-editor-form", %{
      "target_kind" => "control_group",
      "target_id" => control_group["id"],
      "action" => "toggle"
    })
    |> render_change()

    render_click(element(view, "#pico-start-button-learning"))

    Phoenix.PubSub.broadcast(
      Hueworks.PubSub,
      Picos.topic(),
      {:pico_button_press, device.id, "1"}
    )

    assert render(view) =~ "Assigned action to the pressed Pico button."

    buttons = Repo.all(PicoButton) |> Enum.sort_by(& &1.button_number)

    assert device.room_id == override_room.id

    assert Picos.control_groups(Repo.one!(PicoDevice)) == [
             %{
               "group_ids" => [override_group.id],
               "id" => control_group["id"],
               "light_ids" => [],
               "name" => "Overhead"
             }
           ]

    assigned = Enum.find(buttons, &(&1.source_id == "1"))
    assert assigned.action_type == "toggle_any_on"
    assert assigned.action_config["target_kind"] == "control_group"
    assert assigned.action_config["target_id"] == control_group["id"]
  end
end
