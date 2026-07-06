defmodule Hueworks.ImportReimportApplyTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.ReimportApply
  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    Bridge,
    Group,
    GroupLight,
    Light,
    Room,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  defmodule CastReceiver do
    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @impl true
    def init(opts) do
      {:ok, %{label: Keyword.fetch!(opts, :label), sink: Keyword.fetch!(opts, :sink)}}
    end

    @impl true
    def handle_cast(message, state) do
      send(state.sink, {:cast, state.label, message})
      {:noreply, state}
    end
  end

  test "refreshes bridge-owned light fields without changing user-owned fields" do
    bridge = insert_bridge()
    room = insert_room("HueWorks Room")

    existing =
      insert_light(bridge, %{
        name: "Old Bridge Name",
        display_name: "User Name",
        source_id: "light.office",
        room_id: room.id,
        enabled: false,
        ha_export_mode: :switch,
        homekit_export_mode: :switch,
        supports_color: false,
        supports_temp: false,
        external_id: "old-uid"
      })

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.office",
                     name: "New Bridge Name",
                     room_source_id: "bridge-room",
                     capabilities: %{color: true, color_temp: true},
                     metadata: %{"unique_id" => "new-uid"}
                   }
                 ],
                 rooms: [%{source_id: "bridge-room", name: "Bridge Room"}]
               }),
               %{lights: %{"light.office" => true}, groups: %{}, rooms: %{}}
             )

    refreshed = Repo.get!(Light, existing.id)

    assert refreshed.name == "New Bridge Name"
    assert refreshed.display_name == "User Name"
    assert refreshed.room_id == room.id
    assert refreshed.enabled == false
    assert refreshed.ha_export_mode == :switch
    assert refreshed.homekit_export_mode == :switch
    assert refreshed.supports_color == true
    assert refreshed.supports_temp == true
    assert refreshed.external_id == "new-uid"
  end

  test "creates selected new lights in the selected room and skips unselected lights" do
    bridge = insert_bridge()
    room = insert_room("Office")

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 rooms: [%{source_id: "room-office", name: "Office"}],
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.office_display",
                     name: "Office Display",
                     room_source_id: "room-office",
                     metadata: %{"unique_id" => "display-uid"}
                   },
                   %{
                     source: :ha,
                     source_id: "light.ignored",
                     name: "Ignored",
                     room_source_id: "room-office",
                     metadata: %{"unique_id" => "ignored-uid"}
                   }
                 ]
               }),
               %{
                 lights: %{
                   "light.office_display" => %{"selected" => true, "target_room_id" => room.id},
                   "light.ignored" => false
                 },
                 groups: %{},
                 rooms: %{}
               }
             )

    created = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.office_display")

    assert created.name == "Office Display"
    assert created.room_id == room.id
    refute Repo.get_by(Light, bridge_id: bridge.id, source_id: "light.ignored")
  end

  test "reimport-created lights pin display name while bridge name keeps refreshing" do
    bridge = insert_bridge()
    room = insert_room("Office")

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.office_display",
                     name: "Office Display",
                     metadata: %{"unique_id" => "display-uid"}
                   }
                 ]
               }),
               %{
                 lights: %{
                   "light.office_display" => %{"selected" => true, "target_room_id" => room.id}
                 },
                 groups: %{},
                 rooms: %{}
               }
             )

    created = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.office_display")

    assert created.name == "Office Display"
    assert created.display_name == "Office Display"

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.office_display",
                     name: "Renamed Display",
                     metadata: %{"unique_id" => "display-uid"}
                   }
                 ]
               }),
               %{lights: %{"light.office_display" => true}, groups: %{}, rooms: %{}}
             )

    refreshed = Repo.get!(Light, created.id)

    assert refreshed.name == "Renamed Display"
    assert refreshed.display_name == "Office Display"
  end

  test "refreshes group membership from normalized memberships" do
    bridge = insert_bridge()
    room = insert_room("Kitchen")
    light_a = insert_light(bridge, %{source_id: "light.a", room_id: room.id})
    light_b = insert_light(bridge, %{source_id: "light.b", room_id: room.id})

    group =
      insert_group(bridge, %{
        source_id: "group.kitchen",
        room_id: room.id,
        metadata: %{"members" => ["light.a"]}
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{source: :ha, source_id: "light.a", name: "Light A"},
                   %{source: :ha, source_id: "light.b", name: "Light B"}
                 ],
                 groups: [
                   %{source: :ha, source_id: "group.kitchen", name: "Kitchen Group"}
                 ],
                 memberships: %{
                   group_lights: [
                     %{group_source_id: "group.kitchen", light_source_id: "light.b"}
                   ]
                 }
               }),
               %{
                 lights: %{"light.a" => true, "light.b" => true},
                 groups: %{"group.kitchen" => true},
                 rooms: %{}
               }
             )

    assert Repo.all(from(gl in GroupLight, where: gl.group_id == ^group.id, select: gl.light_id)) ==
             [light_b.id]
  end

  test "deletes hidden duplicates that are absent upstream" do
    bridge = insert_bridge()
    canonical = insert_light(bridge, %{source_id: "light.real"})

    hidden =
      insert_light(bridge, %{
        source_id: "light.hidden",
        canonical_light_id: canonical.id,
        enabled: false,
        room_id: nil
      })

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{}),
               %{lights: %{}, groups: %{}, rooms: %{}}
             )

    refute Repo.get(Light, hidden.id)
  end

  test "delete resolution requires an expected external id safety token" do
    bridge = insert_bridge()
    light = insert_light(bridge, %{source_id: "light.delete", external_id: "delete-uid"})

    assert {:error, {:missing_expected_external_id, :light, "light.delete"}} =
             ReimportApply.apply(
               bridge,
               normalized(%{}),
               %{
                 lights: %{"light.delete" => %{"action" => "delete"}},
                 groups: %{},
                 rooms: %{}
               }
             )

    assert Repo.get(Light, light.id)
  end

  test "ambiguous light identity is skipped instead of guessed" do
    bridge = insert_bridge()
    room = insert_room("Office")

    source_match =
      insert_light(bridge, %{
        name: "Source Match",
        source_id: "light.office",
        external_id: "source-match-uid",
        room_id: room.id
      })

    external_match =
      insert_light(bridge, %{
        name: "External Match",
        source_id: "light.other",
        external_id: "incoming-uid",
        room_id: room.id
      })

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.office",
                     name: "Incoming Bridge Name",
                     metadata: %{"unique_id" => "incoming-uid"}
                   }
                 ]
               }),
               %{lights: %{"light.office" => true}, groups: %{}, rooms: %{}}
             )

    assert Repo.get!(Light, source_match.id).name == "Source Match"
    assert Repo.get!(Light, external_match.id).name == "External Match"

    assert Repo.aggregate(
             from(l in Light, where: l.bridge_id == ^bridge.id),
             :count
           ) == 2
  end

  test "duplicate resolutions create hidden duplicates or visible real rows" do
    native_bridge =
      insert_bridge(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.3",
        credentials: %{"api_key" => "api-key"}
      })

    canonical =
      insert_light(native_bridge, %{
        name: "Native Light",
        source: :hue,
        source_id: "hue-light",
        external_id: "native-uid",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc:dd:ee:ff"}}
      })

    bridge = insert_bridge()
    room = insert_room("Office")

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.hidden_duplicate",
                     name: "Hidden Duplicate",
                     identifiers: %{"mac" => "aa:bb:cc:dd:ee:ff"},
                     metadata: %{"unique_id" => "hidden-uid"}
                   },
                   %{
                     source: :ha,
                     source_id: "light.real_duplicate",
                     name: "Real Duplicate",
                     identifiers: %{"mac" => "aa:bb:cc:dd:ee:ff"},
                     metadata: %{"unique_id" => "real-uid"}
                   }
                 ]
               }),
               %{
                 lights: %{
                   "light.hidden_duplicate" => %{
                     "selected" => true,
                     "resolution" => "import_hidden_duplicate"
                   },
                   "light.real_duplicate" => %{
                     "selected" => true,
                     "resolution" => "import_real",
                     "target_room_id" => room.id
                   }
                 },
                 groups: %{},
                 rooms: %{}
               }
             )

    hidden = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.hidden_duplicate")
    real = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.real_duplicate")

    assert hidden.enabled == false
    assert hidden.room_id == nil
    assert hidden.canonical_light_id == canonical.id
    assert hidden.ha_export_mode == :none
    assert hidden.homekit_export_mode == :none

    assert real.enabled == true
    assert real.room_id == room.id
    assert real.canonical_light_id == nil
  end

  test "duplicate classification drift rolls the transaction back" do
    native_bridge =
      insert_bridge(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.3",
        credentials: %{"api_key" => "api-key"}
      })

    insert_light(native_bridge, %{
      source: :hue,
      source_id: "hue-light",
      metadata: %{"identifiers" => %{"mac" => "aa:bb:cc:dd:ee:ff"}}
    })

    bridge = insert_bridge()

    assert {:error, {:duplicate_classification_changed, :light, "light.drifted"}} =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.drifted",
                     name: "Drifted Duplicate",
                     identifiers: %{"mac" => "aa:bb:cc:dd:ee:ff"},
                     metadata: %{"unique_id" => "drifted-uid"}
                   }
                 ]
               }),
               %{
                 lights: %{
                   "light.drifted" => %{"selected" => true, "resolution" => "import"}
                 },
                 groups: %{},
                 rooms: %{}
               }
             )

    refute Repo.get_by(Light, bridge_id: bridge.id, source_id: "light.drifted")
  end

  test "mismatched expected external id rolls destructive resolutions back" do
    bridge = insert_bridge()
    light = insert_light(bridge, %{source_id: "light.disable", external_id: "current-light-uid"})
    group = insert_group(bridge, %{source_id: "group.delete", external_id: "current-group-uid"})

    assert {:error, {:stale_resolution, :light, "light.disable"}} =
             ReimportApply.apply(
               bridge,
               normalized(%{}),
               %{
                 lights: %{
                   "light.disable" => %{
                     "action" => "disable",
                     "expected_external_id" => "stale-light-uid"
                   }
                 },
                 groups: %{
                   "group.delete" => %{
                     "action" => "delete",
                     "expected_external_id" => "stale-group-uid"
                   }
                 },
                 rooms: %{}
               }
             )

    assert Repo.get!(Light, light.id).enabled == true
    assert Repo.get(Group, group.id)
  end

  test "delete resolution cleans scene component and group light references" do
    bridge = insert_bridge()
    room = insert_room("Office")
    light = insert_light(bridge, %{source_id: "light.delete", external_id: "delete-uid"})
    group = insert_group(bridge, %{source_id: "group.office"})

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    scene_component_light = insert_scene_component_light(light, room)

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{}),
               %{
                 lights: %{
                   "light.delete" => %{
                     "action" => "delete",
                     "expected_external_id" => "delete-uid"
                   }
                 },
                 groups: %{},
                 rooms: %{}
               }
             )

    refute Repo.get(Light, light.id)
    refute Repo.get_by(GroupLight, group_id: group.id, light_id: light.id)
    refute Repo.get(SceneComponentLight, scene_component_light.id)
  end

  test "post-commit effects are emitted only for destructive resolutions and cover every removal" do
    start_cast_receiver(Hueworks.HomeAssistant.Export, :ha_export)
    start_cast_receiver(Hueworks.HomeKit.Bridge, :homekit)

    bridge = insert_bridge()
    room = insert_room("Office")

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{
                 lights: [
                   %{
                     source: :ha,
                     source_id: "light.created",
                     name: "Created",
                     metadata: %{"unique_id" => "created-uid"}
                   }
                 ]
               }),
               %{
                 lights: %{
                   "light.created" => %{"selected" => true, "target_room_id" => room.id}
                 },
                 groups: %{},
                 rooms: %{}
               }
             )

    refute_receive {:cast, _label, _message}, 50

    disabled_light =
      insert_light(bridge, %{source_id: "light.disable", external_id: "disable-light-uid"})

    deleted_light =
      insert_light(bridge, %{source_id: "light.delete", external_id: "delete-light-uid"})

    disabled_group =
      insert_group(bridge, %{source_id: "group.disable", external_id: "disable-group-uid"})

    deleted_group =
      insert_group(bridge, %{source_id: "group.delete", external_id: "delete-group-uid"})

    disabled_light_id = disabled_light.id
    deleted_light_id = deleted_light.id
    disabled_group_id = disabled_group.id
    deleted_group_id = deleted_group.id

    assert :ok =
             ReimportApply.apply(
               bridge,
               normalized(%{}),
               %{
                 lights: %{
                   "light.disable" => %{
                     "action" => "disable",
                     "expected_external_id" => "disable-light-uid"
                   },
                   "light.delete" => %{
                     "action" => "delete",
                     "expected_external_id" => "delete-light-uid"
                   }
                 },
                 groups: %{
                   "group.disable" => %{
                     "action" => "disable",
                     "expected_external_id" => "disable-group-uid"
                   },
                   "group.delete" => %{
                     "action" => "delete",
                     "expected_external_id" => "delete-group-uid"
                   }
                 },
                 rooms: %{}
               }
             )

    assert_receive {:cast, :ha_export, {:remove_light, ^disabled_light_id}}
    assert_receive {:cast, :ha_export, {:remove_light, ^deleted_light_id}}
    assert_receive {:cast, :ha_export, {:remove_group, ^disabled_group_id}}
    assert_receive {:cast, :ha_export, {:remove_group, ^deleted_group_id}}
    assert_receive {:cast, :ha_export, :reload}
    assert_receive {:cast, :homekit, :reload}
    refute_receive {:cast, _label, _message}, 50
  end

  defp normalized(overrides) do
    %{
      rooms: [],
      lights: [],
      groups: [],
      memberships: %{}
    }
    |> Map.merge(overrides)
  end

  defp insert_bridge(attrs \\ %{}) do
    defaults = %{
      type: :ha,
      name: "Home Assistant",
      host: "10.0.0.2",
      credentials: %{"token" => "token"},
      import_complete: true,
      enabled: true
    }

    %Bridge{}
    |> Bridge.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_room(name), do: Repo.insert!(%Room{name: name})

  defp insert_light(bridge, attrs) do
    defaults = %{
      name: "Existing Light",
      source: :ha,
      source_id: "light.existing",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{},
      normalized_json: %{}
    }

    %Light{}
    |> Light.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_group(bridge, attrs) do
    defaults = %{
      name: "Existing Group",
      source: :ha,
      source_id: "group.existing",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{},
      normalized_json: %{}
    }

    %Group{}
    |> Group.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_scene_component_light(light, room) do
    scene =
      %Scene{}
      |> Scene.changeset(%{name: "Evening", room_id: room.id})
      |> Repo.insert!()

    component =
      %SceneComponent{}
      |> SceneComponent.changeset(%{
        scene_id: scene.id,
        embedded_manual_config: %{
          "mode" => "temperature",
          "brightness" => 50,
          "temperature" => 3000
        }
      })
      |> Repo.insert!()

    %SceneComponentLight{}
    |> SceneComponentLight.changeset(%{
      scene_component_id: component.id,
      light_id: light.id,
      default_power: :default_on
    })
    |> Repo.insert!()
  end

  defp start_cast_receiver(name, label) do
    start_supervised!(
      {CastReceiver, name: name, label: label, sink: self()},
      id: {CastReceiver, label}
    )
  end
end
