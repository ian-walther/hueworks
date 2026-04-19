defmodule HueworksWeb.PicoConfigLiveTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.Picos
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.PicoButton.ActionConfig, as: StoredActionConfig
  alias Hueworks.Schemas.{Group, GroupLight, Light, PicoButton, PicoDevice, Room}

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

  defp insert_pico_button(attrs) do
    %PicoButton{}
    |> PicoButton.changeset(attrs)
    |> Repo.insert!()
  end

  test "config page shows Pico Config button for Caseta bridges", %{conn: conn} do
    insert_bridge!(%{
      type: :caseta,
      name: "Caseta",
      host: "10.0.0.60",
      credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
      enabled: true,
      import_complete: true
    })

    insert_bridge!(%{
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

  test "pico config uses a dedicated detail page for editing", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Main Floor"})
    override_room = Repo.insert!(%Room{name: "Override Room"})

    bridge =
      insert_bridge!(%{
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

    _other_device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        source_id: "device-2",
        name: "Hallway Pico",
        room_id: room.id,
        metadata: %{},
        hardware_profile: "5_button",
        enabled: true
      })

    html = render(view)
    assert html =~ "Main Floor Pico"
    refute html =~ "Control Groups"

    device = Repo.get_by!(PicoDevice, source_id: "device-1")

    render_click(element(view, "button[phx-click='select_pico']"))

    assert_patch(view, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    html = render(view)
    assert html =~ "Configure Pico"
    assert html =~ "Control Groups"
    assert html =~ "hw-section-block"
    assert html =~ ~s(class="hw-pico-section-row")
    assert String.contains?(html, "Room Scope")
    assert String.contains?(html, "Clone From Another Pico")
    assert match?({_, _}, :binary.match(html, "Room Scope"))
    assert match?({_, _}, :binary.match(html, "Clone From Another Pico"))
    assert :binary.match(html, "Room Scope") < :binary.match(html, "Clone From Another Pico")
    assert html =~ "Main Floor (Auto-Detected)"
    assert html =~ ~s(id="pico-clone-source-form")
    refute html =~ "hw-inline-control-stack-mobile"
    refute html =~ "Pico room updated."

    view
    |> form("form[phx-change='save_room_override']", %{
      "room_id" => Integer.to_string(override_room.id)
    })
    |> render_change()

    assert render(view) =~ "Pico room updated."

    render_click(element(view, "#pico-create-control-group"))

    assert render(view) =~ "Control group created."
    assert render(view) =~ "Control Group 1"
    assert has_element?(view, "#pico-control-group-group-form")

    view
    |> form("#pico-control-group-group-form form", %{
      "entity" => "group",
      "id" => Integer.to_string(override_group.id)
    })
    |> render_change()

    assert render(view) =~ "Override Overhead Group"
    refute render(view) =~ "Save Control Group"

    device = Repo.get_by!(PicoDevice, source_id: "device-1")
    [control_group] = Picos.control_groups(device)

    view
    |> form("#pico-binding-editor-form", %{
      "action" => "toggle",
      "target_ids" => [control_group["id"]]
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

    assert Picos.control_groups(Repo.get_by!(PicoDevice, source_id: "device-1")) == [
             %{
               "group_ids" => [override_group.id],
               "id" => control_group["id"],
               "light_ids" => [],
               "name" => "Control Group 1"
             }
           ]

    assigned = Enum.find(buttons, &(&1.source_id == "1"))
    assert assigned.action_type == "toggle_any_on"

    assert %StoredActionConfig{
             target_kind: :control_groups,
             target_ids: control_group_ids
           } = PicoButton.action_config_struct(assigned)

    assert control_group_ids == [control_group["id"]]
  end

  test "selecting control group lights adds them immediately", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Bedroom"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.69",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    light =
      Repo.insert!(%Light{
        name: "Nightstand",
        source: :caseta,
        source_id: "69",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "bedroom-pico",
        name: "Bedroom Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Bedroom", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    render_click(element(view, "#pico-edit-control-group-group-a"))

    view
    |> form("#pico-control-group-light-form form", %{
      "entity" => "light",
      "id" => Integer.to_string(light.id)
    })
    |> render_change()

    assert render(view) =~ "Nightstand"

    assert [
             %{
               "name" => "Bedroom",
               "group_ids" => [],
               "light_ids" => light_ids
             }
           ] = Picos.control_groups(Picos.get_device(device.id))

    assert light_ids == [light.id]
  end

  test "control group names can be edited inline", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.694",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "office-pico",
        name: "Office Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Overhead", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    refute has_element?(view, "#pico-edit-control-group-name-form")
    refute has_element?(view, "#pico-start-control-group-name-edit")
    assert render(view) =~ "Overhead"

    render_click(element(view, "#pico-edit-control-group-group-a"))

    render_click(element(view, "#pico-start-control-group-name-edit"))

    assert has_element?(view, "#pico-edit-control-group-name-form")

    view
    |> form("#pico-edit-control-group-name-form", %{"name" => "Accent"})
    |> render_submit()

    assert [
             %{
               "group_ids" => [],
               "id" => "group-a",
               "light_ids" => [],
               "name" => "Accent"
             }
           ] = Picos.control_groups(Picos.get_device(device.id))

    assert render(view) =~ "Control group name updated."
    refute has_element?(view, "#pico-edit-control-group-name-form")
    assert render(view) =~ "Accent"
  end

  test "creating control groups auto-generates the next available name", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Den"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.695",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "den-pico",
        name: "Den Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Control Group 1", "group_ids" => [], "light_ids" => []},
            %{"id" => "group-b", "name" => "Reading", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    render_click(element(view, "#pico-create-control-group"))

    assert render(view) =~ "Control group created."
    assert render(view) =~ "Control Group 2"
    assert render(view) =~ "Done"

    assert Enum.any?(
             Picos.control_groups(Picos.get_device(device.id)),
             &(&1["name"] == "Control Group 2")
           )
  end

  test "add light dropdown excludes lights already covered by selected groups", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Hallway"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.691",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    light_a =
      Repo.insert!(%Light{
        name: "Hallway Ceiling 1-1",
        source: :caseta,
        source_id: "691",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    _light_b =
      Repo.insert!(%Light{
        name: "Hallway Ceiling 1-2",
        source: :caseta,
        source_id: "692",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    group =
      Repo.insert!(%Group{
        name: "Hallway",
        source: :caseta,
        source_id: "group-691",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "hallway-pico",
        name: "Hallway Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{
              "id" => "group-a",
              "name" => "Overhead",
              "group_ids" => [group.id],
              "light_ids" => []
            }
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    render_click(element(view, "#pico-edit-control-group-group-a"))

    light_select_html = render(view |> element("#pico-control-group-light-form"))

    refute light_select_html =~ "Hallway Ceiling 1-1"
    assert light_select_html =~ "Hallway Ceiling 1-2"
  end

  test "add group dropdown excludes groups that overlap already selected direct lights", %{
    conn: conn
  } do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.692",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    light_a =
      Repo.insert!(%Light{
        name: "Kitchen Ceiling 1",
        source: :caseta,
        source_id: "693",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    light_b =
      Repo.insert!(%Light{
        name: "Kitchen Ceiling 2",
        source: :caseta,
        source_id: "694",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    overlap_group =
      Repo.insert!(%Group{
        name: "Kitchen Ceiling",
        source: :caseta,
        source_id: "group-692",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    isolated_group =
      Repo.insert!(%Group{
        name: "Kitchen Accent",
        source: :caseta,
        source_id: "group-693",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: overlap_group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: isolated_group.id, light_id: light_b.id})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "kitchen-pico",
        name: "Kitchen Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{
              "id" => "group-a",
              "name" => "Custom",
              "group_ids" => [],
              "light_ids" => [light_a.id]
            }
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    render_click(element(view, "#pico-edit-control-group-group-a"))

    group_select_html = render(view |> element("#pico-control-group-group-form"))

    refute group_select_html =~ "Kitchen Ceiling"
    assert group_select_html =~ "Kitchen Accent"
  end

  test "add group dropdown hides after selecting the last group with uncovered lights", %{
    conn: conn
  } do
    room = Repo.insert!(%Room{name: "Living Room"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.693",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "695",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    useful_group =
      Repo.insert!(%Group{
        name: "Lamp Group",
        source: :caseta,
        source_id: "group-694",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    Repo.insert!(%GroupLight{group_id: useful_group.id, light_id: light.id})

    Repo.insert!(%Group{
      name: "Empty Group",
      source: :caseta,
      source_id: "group-695",
      bridge_id: bridge.id,
      room_id: room.id,
      enabled: true
    })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "living-room-pico",
        name: "Living Room Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Custom", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    render_click(element(view, "#pico-edit-control-group-group-a"))

    assert has_element?(view, "#pico-control-group-group-form")

    view
    |> form("#pico-control-group-group-form form", %{
      "entity" => "group",
      "id" => Integer.to_string(useful_group.id)
    })
    |> render_change()

    html = render(view)

    refute has_element?(view, "#pico-control-group-group-form")
    refute html =~ "Add group"
    refute html =~ "Select group"
  end

  test "control group inputs only show inside the card being edited", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Family Room"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.696",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "family-room-pico",
        name: "Family Room Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Overhead", "group_ids" => [], "light_ids" => []},
            %{"id" => "group-b", "name" => "Lamps", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    refute has_element?(view, "#pico-control-group-group-form")
    assert has_element?(view, "#pico-edit-control-group-group-b", "Edit")
    refute has_element?(view, "#pico-start-control-group-name-edit")

    render_click(element(view, "#pico-edit-control-group-group-b"))

    assert has_element?(view, "#pico-edit-control-group-group-b", "Done")
    refute has_element?(view, "#pico-edit-control-group-group-a", "Done")
    assert has_element?(view, "#pico-start-control-group-name-edit")

    render_click(element(view, "#pico-edit-control-group-group-b"))

    assert has_element?(view, "#pico-edit-control-group-group-b", "Edit")
    refute has_element?(view, "#pico-start-control-group-name-edit")
    refute has_element?(view, "#pico-edit-control-group-group-b", "Done")
  end

  test "pico config saves and displays Pico display_name with fallback to name", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Main Floor"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.621",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "rename-pico",
        name: "Front Hall Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    assert html =~ "Front Hall Pico"
    refute has_element?(view, "#pico-display-name-form")

    render_click(element(view, "#pico-start-display-name-edit"))

    assert has_element?(view, "#pico-display-name-form")
    assert has_element?(view, "#pico-save-display-name")
    assert has_element?(view, "#pico-cancel-display-name")

    view
    |> form("#pico-display-name-form", %{"display_name" => "Entry Pico"})
    |> render_submit()

    assert render(view) =~ "Pico name updated."
    assert render(view) =~ "Entry Pico"
    refute render(view) =~ "Front Hall Pico</h2>"
    refute has_element?(view, "#pico-display-name-form")

    reloaded = Repo.get!(PicoDevice, device.id)
    assert reloaded.display_name == "Entry Pico"

    {:ok, list_view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos")
    assert render(list_view) =~ "Entry Pico"

    render_click(element(view, "#pico-start-display-name-edit"))

    view
    |> form("#pico-display-name-form", %{"display_name" => "   "})
    |> render_submit()

    assert Repo.get!(PicoDevice, device.id).display_name == nil
    assert render(view) =~ "Front Hall Pico"
  end

  test "room override saves immediately on selection", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Main Floor"})
    override_room = Repo.insert!(%Room{name: "Library"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.622",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "auto-save-room-pico",
        name: "Auto Save Room Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => false, "detected_room_id" => room.id}
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    view
    |> form("form[phx-change='save_room_override']", %{
      "room_id" => Integer.to_string(override_room.id)
    })
    |> render_change()

    updated = Repo.get!(PicoDevice, device.id)
    assert updated.room_id == override_room.id
    assert render(view) =~ "Pico room updated."
  end

  test "room selector shows disabled dash when no room can be auto-detected", %{conn: conn} do
    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.72",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    _room = Repo.insert!(%Room{name: "Hallway"})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        source_id: "device-no-detected-room",
        name: "No Room Pico",
        room_id: nil,
        metadata: %{"room_override" => false},
        hardware_profile: "5_button",
        enabled: true
      })

    {:ok, _view, html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    assert html =~ ~s(<option value="" selected="selected" disabled="disabled">)
    assert html =~ "<option value=\"\" selected=\"selected\" disabled=\"disabled\">"
    assert html =~ "\n-\n"
    assert html =~ ~s(id="pico-clear-room-scope")

    assert html =~
             ~s(id="pico-clear-room-scope" type="button" class="hw-button hw-delete-button" phx-click="clear_pico_config" disabled)

    assert html =~
             "This Pico needs a room before control groups or button bindings can be configured."

    assert html =~ "Hallway"
  end

  test "room override is locked until existing pico config is cleared", %{conn: conn} do
    auto_room = Repo.insert!(%Room{name: "Auto Room"})
    new_room = Repo.insert!(%Room{name: "New Room"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.623",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: new_room.id,
        source_id: "locked-room-pico",
        name: "Locked Room Pico",
        hardware_profile: "5_button",
        metadata: %{
          "detected_room_id" => auto_room.id,
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Accent", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    button =
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "b1",
        button_number: 2,
        slot_index: 0,
        action_type: "toggle_any_on",
        action_config: %{"target_kind" => "control_groups", "target_ids" => ["group-a"]},
        enabled: true
      })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    html = render(view)
    assert html =~ "pico-clear-room-scope"
    assert html =~ "Clear"
    assert html =~ ~s(id="pico-room-id")
    assert html =~ ~s(id="pico-clear-room-scope")

    view
    |> element("#pico-clear-room-scope")
    |> render_click()

    updated = Repo.get!(PicoDevice, device.id)
    updated_button = Repo.get!(PicoButton, button.id)

    assert updated.room_id == auto_room.id
    assert render(view) =~ "pico-clear-room-scope"
    assert render(view) =~ "Clear"
    assert render(view) =~ "Pico config cleared."
    assert updated_button.action_type == nil

    view
    |> form("form[phx-change='save_room_override']", %{
      "room_id" => Integer.to_string(new_room.id)
    })
    |> render_change()

    assert Repo.get!(PicoDevice, device.id).room_id == new_room.id
    assert render(view) =~ "Pico room updated."
  end

  test "detect pico mode redirects from the list page into the matching pico config", %{
    conn: conn
  } do
    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.63",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos")

    render_click(element(view, "button[phx-click='sync_picos']"))
    assert render(view) =~ "Main Floor Pico"

    render_click(element(view, "#pico-start-detect"))
    assert render(view) =~ "Detect mode active. Press a Pico button to open that Pico."

    device = Repo.one!(PicoDevice)

    Phoenix.PubSub.broadcast(
      Hueworks.PubSub,
      Picos.topic(),
      {:pico_button_press, device.id, "1"}
    )

    assert_patch(view, "/config/bridge/#{bridge.id}/picos/#{device.id}")
    html = render(view)
    assert html =~ "Configure Pico"
    assert html =~ "Pico detected. Opening configuration."
  end

  test "pico config can be cloned from another pico on the detail page", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Main Floor"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.64",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    light =
      Repo.insert!(%Light{
        name: "Overhead",
        source: :caseta,
        source_id: "42",
        bridge_id: bridge.id,
        room_id: room.id,
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

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})

    source =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "source-pico",
        name: "Source Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    destination =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "destination-pico",
        name: "Destination Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    for {device_id, source_id, button_number, slot_index} <- [
          {source.id, "s1", 2, 0},
          {source.id, "s2", 3, 1},
          {destination.id, "d1", 2, 0},
          {destination.id, "d2", 3, 1}
        ] do
      insert_pico_button(%{
        pico_device_id: device_id,
        source_id: source_id,
        button_number: button_number,
        slot_index: slot_index,
        enabled: true
      })
    end

    {:ok, source} =
      Picos.save_control_group(source, %{
        "name" => "Overhead",
        "group_ids" => [group.id],
        "light_ids" => []
      })

    [control_group] = Picos.control_groups(source)

    {:ok, _button} =
      Picos.assign_button_binding(source, "s1", %{
        "action" => "toggle",
        "target_kind" => "control_groups",
        "target_ids" => [control_group["id"]]
      })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{destination.id}")

    assert render(view) =~ "Clone From Another Pico"
    assert render(view) =~ "Source Pico"

    view
    |> form("#pico-clone-source-form", %{"id" => Integer.to_string(source.id)})
    |> render_change()

    render_click(element(view, "#pico-clone-config"))

    assert [
             %{
               "group_ids" => group_ids,
               "light_ids" => [],
               "name" => "Overhead"
             }
           ] = Picos.control_groups(Picos.get_device(destination.id))

    assert group_ids == [group.id]

    html = render(view)
    assert html =~ "Pico config copied."
    assert html =~ "Overhead"
    assert html =~ "Toggle Overhead"
  end

  test "pico control group dropdowns hide disabled and linked targets", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.65",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    root_light =
      Repo.insert!(%Light{
        name: "Desk Lamp",
        source: :caseta,
        source_id: "51",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    _disabled_light =
      Repo.insert!(%Light{
        name: "Disabled Lamp",
        source: :caseta,
        source_id: "52",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: false
      })

    _linked_light =
      Repo.insert!(%Light{
        name: "Linked Lamp",
        source: :caseta,
        source_id: "53",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true,
        canonical_light_id: root_light.id
      })

    enabled_group =
      Repo.insert!(%Group{
        name: "Desk Group",
        source: :caseta,
        source_id: "group-51",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: true
      })

    _disabled_group =
      Repo.insert!(%Group{
        name: "Disabled Group",
        source: :caseta,
        source_id: "group-52",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: false
      })

    Repo.insert!(%GroupLight{group_id: enabled_group.id, light_id: root_light.id})

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "office-pico",
        name: "Office Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Overhead", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    render_click(element(view, "#pico-edit-control-group-group-a"))

    html = render(view)

    assert html =~ "Desk Lamp"
    assert html =~ "Desk Group"
    refute html =~ "Disabled Lamp"
    refute html =~ "Linked Lamp"
    refute html =~ "Disabled Group"
  end

  test "pico config can bind a button press to a room scene", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Movie Room"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.66",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "movie-pico",
        name: "Movie Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, state} =
      Scenes.create_manual_light_state("Movie", %{"brightness" => "25", "temperature" => "2600"})

    {:ok, scene} = Scenes.create_scene(%{name: "Movie Night", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{light_state_id: to_string(state.id), light_ids: []}
      ])

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    view
    |> form("#pico-binding-editor-form", %{"action" => "activate_scene"})
    |> render_change()

    html =
      view
      |> form("#pico-binding-editor-form", %{
        "action" => "activate_scene",
        "target_id" => Integer.to_string(scene.id)
      })
      |> render_change()

    assert html =~ "Movie Night"
    assert html =~ "Activate Scene"

    render_click(element(view, "#pico-start-button-learning"))

    Phoenix.PubSub.broadcast(
      Hueworks.PubSub,
      Picos.topic(),
      {:pico_button_press, device.id, "b1"}
    )

    assert render(view) =~ "Assigned action to the pressed Pico button."
    assert render(view) =~ "Activate Scene Movie Night"

    button = Repo.one!(PicoButton)
    assert button.action_type == "activate_scene"

    assert %StoredActionConfig{target_kind: :scene, scene_id: scene_id} =
             PicoButton.action_config_struct(button)

    assert scene_id == scene.id
  end

  test "bind button by press uses control-group checkboxes", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.661",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "checkbox-pico",
        name: "Checkbox Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Overhead", "group_ids" => [], "light_ids" => []},
            %{"id" => "group-b", "name" => "Lamps", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, view, html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    assert html =~ ~s(id="pico-binding-target-groups")
    assert html =~ ~s(name="target_ids[]")
    refute html =~ "Target scope"
    refute html =~ "One Control Group"
    refute html =~ "All Control Groups"

    view
    |> form("#pico-binding-editor-form", %{
      "action" => "toggle",
      "target_ids" => ["group-a", "group-b"]
    })
    |> render_change()

    render_click(element(view, "#pico-start-button-learning"))

    Phoenix.PubSub.broadcast(
      Hueworks.PubSub,
      Picos.topic(),
      {:pico_button_press, device.id, "b1"}
    )

    assert render(view) =~ "Assigned action to the pressed Pico button."
    assert render(view) =~ "Toggle Overhead + Lamps"
  end

  test "discovered buttons can be assigned manually from the current binding editor state", %{
    conn: conn
  } do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.662",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "manual-assign-pico",
        name: "Manual Assign Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Overhead", "group_ids" => [], "light_ids" => []},
            %{"id" => "group-b", "name" => "Lamps", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    button =
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "b1",
        button_number: 2,
        slot_index: 0,
        enabled: true
      })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    view
    |> form("#pico-binding-editor-form", %{
      "action" => "toggle",
      "target_ids" => ["group-a", "group-b"]
    })
    |> render_change()

    view
    |> element("#pico-manual-assign-button-#{button.id}")
    |> render_click()

    assert render(view) =~ "Assigned action to the selected Pico button."
    assert render(view) =~ "Toggle Overhead + Lamps"

    updated = Repo.get!(PicoButton, button.id)
    assert updated.action_type == "toggle_any_on"

    assert %StoredActionConfig{target_kind: :control_groups, target_ids: target_ids} =
             PicoButton.action_config_struct(updated)

    assert target_ids == ["group-a", "group-b"]
  end

  test "pico config can delete a control group", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Studio"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.67",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "delete-pico",
        name: "Delete Pico",
        hardware_profile: "5_button",
        metadata: %{
          "room_override" => true,
          "control_groups" => [
            %{"id" => "group-a", "name" => "Overhead", "group_ids" => [], "light_ids" => []}
          ]
        }
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "b1",
      button_number: 2,
      slot_index: 0,
      enabled: true
    })

    {:ok, _button} =
      Picos.assign_button_binding(device, "b1", %{
        "action" => "toggle",
        "target_kind" => "control_groups",
        "target_ids" => ["group-a"]
      })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    assert render(view) =~ "Overhead"
    assert render(view) =~ "Toggle Overhead"

    view
    |> element("button[phx-click='delete_control_group'][phx-value-id='group-a']")
    |> render_click()

    assert render(view) =~ "Control group deleted."
    refute render(view) =~ "Toggle Overhead"
    refute has_element?(view, "button[phx-click='select_control_group'][phx-value-id='group-a']")
    assert render(view) =~ "binding: Not assigned"
    assert Picos.control_groups(Picos.get_device(device.id)) == []
  end

  test "pico config can clear a learned button binding", %{conn: conn} do
    room = Repo.insert!(%Room{name: "Movie Room"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.68",
        credentials: %{"cert_path" => "a", "key_path" => "b", "cacert_path" => "c"},
        enabled: true,
        import_complete: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        room_id: room.id,
        source_id: "clear-pico",
        name: "Clear Pico",
        hardware_profile: "5_button",
        metadata: %{"room_override" => true}
      })

    button =
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "b1",
        button_number: 2,
        slot_index: 0,
        enabled: true
      })

    {:ok, state} =
      Scenes.create_manual_light_state("Movie", %{"brightness" => "25", "temperature" => "2600"})

    {:ok, scene} = Scenes.create_scene(%{name: "Movie Night", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{light_state_id: to_string(state.id), light_ids: []}
      ])

    {:ok, _button} =
      Picos.assign_button_binding(device, "b1", %{
        "action" => "activate_scene",
        "target_kind" => "scene",
        "target_id" => scene.id
      })

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    assert render(view) =~ "Activate Scene Movie Night"

    view
    |> element("button[phx-click='clear_button_binding'][phx-value-id='#{button.id}']")
    |> render_click()

    updated = Repo.get!(PicoButton, button.id)
    assert updated.action_type == nil
    assert render(view) =~ "Button binding cleared."
    assert render(view) =~ "binding: Not assigned"
  end
end
