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

    html = render(view)
    assert html =~ "Main Floor Pico"
    refute html =~ "Control Groups"

    device = Repo.one!(PicoDevice)

    render_click(element(view, "button[phx-click='select_pico']"))

    assert_patch(view, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    html = render(view)
    assert html =~ "Configure Pico"
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

    assert %StoredActionConfig{
             target_kind: :control_group,
             control_group_id: control_group_id
           } = PicoButton.action_config_struct(assigned)

    assert control_group_id == control_group["id"]
  end

  test "detect pico mode redirects from the list page into the matching pico config", %{conn: conn} do
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
        "target_kind" => "control_group",
        "target_id" => control_group["id"]
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

    _enabled_group =
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
    {:ok, _} = Scenes.replace_scene_components(scene, [%{light_state_id: to_string(state.id), light_ids: []}])

    {:ok, view, _html} = live(conn, "/config/bridge/#{bridge.id}/picos/#{device.id}")

    view
    |> form("#pico-binding-editor-form", %{"target_kind" => "scene"})
    |> render_change()

    html =
      view
      |> form("#pico-binding-editor-form", %{
        "target_kind" => "scene",
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
end
