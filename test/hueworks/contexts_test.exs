defmodule Hueworks.ContextsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.AppSettings
  alias Hueworks.Bridges
  alias Hueworks.Lights
  alias Hueworks.Groups
  alias Hueworks.Rooms
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, Bridge, BridgeImport, Group, GroupLight, Light, Room}

  defp insert_bridge(attrs) do
    defaults = %{
      type: :hue,
      name: "Hue Bridge",
      host: "192.168.1.10",
      credentials: %{"api_key" => "abc"},
      enabled: true,
      import_complete: false
    }

    Repo.insert!(struct(Bridge, Map.merge(defaults, attrs)))
  end

  defp insert_light(bridge, attrs) do
    defaults = %{
      name: "Light",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{}
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  defp insert_group(bridge, attrs) do
    defaults = %{
      name: "Group",
      source: :hue,
      source_id: "g1",
      bridge_id: bridge.id,
      enabled: true,
      metadata: %{}
    }

    Repo.insert!(struct(Group, Map.merge(defaults, attrs)))
  end

  defp insert_room(name) do
    Repo.insert!(%Room{name: name})
  end

  defp insert_bridge_import(bridge, attrs) do
    defaults = %{
      raw_blob: %{"bridge" => bridge.name},
      normalized_blob: %{"bridge" => bridge.name},
      review_blob: %{},
      status: :normalized,
      imported_at: ~U[2026-03-19 12:00:00Z]
    }

    Repo.insert!(struct(BridgeImport, Map.merge(defaults, Map.put(attrs, :bridge_id, bridge.id))))
  end

  test "Lights.list_controllable_lights filters canonical and canonical-group lights" do
    bridge = insert_bridge(%{host: "10.0.0.10"})

    light_a = insert_light(bridge, %{source_id: "a"})
    _light_b = insert_light(bridge, %{source_id: "b", canonical_light_id: light_a.id})

    canonical_group = insert_group(bridge, %{source_id: "g2"})
    group = insert_group(bridge, %{source_id: "g3", canonical_group_id: canonical_group.id})
    light_c = insert_light(bridge, %{source_id: "c"})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_c.id})

    lights = Lights.list_controllable_lights()

    assert Enum.map(lights, & &1.source_id) == ["a"]
  end

  test "Lights.list_controllable_lights include_disabled includes disabled lights" do
    bridge = insert_bridge(%{host: "10.0.0.11"})

    _enabled = insert_light(bridge, %{source_id: "a", enabled: true})
    _disabled = insert_light(bridge, %{source_id: "b", enabled: false})

    ids_default = Lights.list_controllable_lights() |> Enum.map(& &1.source_id)
    ids_all = Lights.list_controllable_lights(true) |> Enum.map(& &1.source_id)

    assert ids_default == ["a"]
    assert Enum.sort(ids_all) == ["a", "b"]
  end

  test "Lights.list_controllable_lights can include linked lights" do
    bridge = insert_bridge(%{host: "10.0.0.111"})
    root = insert_light(bridge, %{source_id: "a"})
    _linked = insert_light(bridge, %{source_id: "b", canonical_light_id: root.id})

    ids_default = Lights.list_controllable_lights(true) |> Enum.map(& &1.source_id)
    ids_all = Lights.list_controllable_lights(true, true) |> Enum.map(& &1.source_id)

    assert ids_default == ["a"]
    assert Enum.sort(ids_all) == ["a", "b"]
  end

  test "Lights.update_display_name normalizes blanks and allows HA kelvin overrides" do
    ha_bridge = insert_bridge(%{type: :ha, host: "10.0.0.12", credentials: %{"token" => "t"}})
    ha_light = insert_light(ha_bridge, %{source: :ha, source_id: "light.kitchen"})

    {:ok, updated} =
      Lights.update_display_name(ha_light, %{
        display_name: "  ",
        actual_min_kelvin: "2200",
        actual_max_kelvin: 5000
      })

    assert updated.display_name == nil
    assert updated.actual_min_kelvin == 2200
    assert updated.actual_max_kelvin == 5000
  end

  test "Lights.update_display_name allows Z2M kelvin overrides" do
    z2m_bridge =
      insert_bridge(%{
        type: :z2m,
        host: "10.0.0.121",
        credentials: %{"broker_port" => 1883}
      })

    z2m_light = insert_light(z2m_bridge, %{source: :z2m, source_id: "kitchen.strip"})

    {:ok, updated} =
      Lights.update_display_name(z2m_light, %{
        actual_min_kelvin: "2100",
        actual_max_kelvin: 6100
      })

    assert updated.actual_min_kelvin == 2100
    assert updated.actual_max_kelvin == 6100
  end

  test "Lights.update_display_name rejects actual kelvin for non-HA/Z2M sources" do
    bridge = insert_bridge(%{host: "10.0.0.13"})
    light = insert_light(bridge, %{source: :hue, source_id: "1"})

    assert {:error, changeset} =
             Lights.update_display_name(light, %{actual_min_kelvin: 2200})

    assert changeset.errors[:actual_min_kelvin] != nil
  end

  test "Lights.update_link links to a canonical root and rejects chains" do
    bridge = insert_bridge(%{host: "10.0.0.131"})
    root = insert_light(bridge, %{source_id: "root"})
    child = insert_light(bridge, %{source_id: "child"})

    assert {:ok, updated} = Lights.update_link(child, root.id)
    assert updated.canonical_light_id == root.id

    middle = insert_light(bridge, %{source_id: "middle"})
    dependent = insert_light(bridge, %{source_id: "dependent", canonical_light_id: middle.id})

    assert {:error, :has_linked_dependents} = Lights.update_link(middle, root.id)
    assert Repo.get!(Light, dependent.id).canonical_light_id == middle.id
  end

  test "Lights.list_link_targets excludes self and non-root lights" do
    bridge = insert_bridge(%{host: "10.0.0.132"})
    root = insert_light(bridge, %{source_id: "root"})
    other_root = insert_light(bridge, %{source_id: "other"})
    child = insert_light(bridge, %{source_id: "child", canonical_light_id: root.id})

    targets = Lights.list_link_targets(root)

    assert Enum.map(targets, & &1.id) == [other_root.id]
    refute Enum.any?(targets, &(&1.id == root.id))
    refute Enum.any?(targets, &(&1.id == child.id))
  end

  test "Groups.list_controllable_groups filters canonical and disabled groups" do
    bridge = insert_bridge(%{host: "10.0.0.14"})

    base = insert_group(bridge, %{source_id: "g1"})
    _canonical = insert_group(bridge, %{source_id: "g2", canonical_group_id: base.id})
    _disabled = insert_group(bridge, %{source_id: "g3", enabled: false})

    ids_default = Groups.list_controllable_groups() |> Enum.map(& &1.source_id)
    ids_all = Groups.list_controllable_groups(true) |> Enum.map(& &1.source_id)

    assert ids_default == ["g1"]
    assert Enum.sort(ids_all) == ["g1", "g3"]
  end

  test "Groups.update_display_name normalizes blanks and syncs room to member lights" do
    bridge = insert_bridge(%{host: "10.0.0.15"})
    room = insert_room("Living")
    group = insert_group(bridge, %{source_id: "g1"})
    light = insert_light(bridge, %{source_id: "l1", room_id: nil})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})

    {:ok, updated} = Groups.update_display_name(group, %{display_name: "  ", room_id: room.id})

    assert updated.display_name == nil
    assert Repo.get!(Light, light.id).room_id == room.id
  end

  test "Rooms context supports CRUD and list ordering" do
    _b = insert_room("B room")
    _a = insert_room("A room")

    names = Rooms.list_rooms() |> Enum.map(& &1.name)
    assert names == ["A room", "B room"]

    {:ok, room} = Rooms.create_room(%{name: "Office"})
    {:ok, updated} = Rooms.update_room(room, %{name: "Office 2"})
    assert updated.name == "Office 2"

    assert {:ok, _} = Rooms.delete_room(updated)
    assert Rooms.get_room(updated.id) == nil
  end

  test "Bridges.latest_import and list_imports_for_bridge return newest imports first" do
    bridge = insert_bridge(%{host: "10.0.0.16"})

    older =
      insert_bridge_import(bridge, %{imported_at: ~U[2026-03-19 12:00:00Z], status: :normalized})

    newest =
      insert_bridge_import(bridge, %{imported_at: ~U[2026-03-19 12:05:00Z], status: :applied})

    _other_bridge = insert_bridge(%{host: "10.0.0.17"})

    assert Bridges.latest_import(bridge).id == newest.id

    assert Bridges.list_imports_for_bridge(bridge)
           |> Enum.map(& &1.id) == [newest.id, older.id]

    assert Bridges.list_imports_for_bridge(bridge, status: :applied)
           |> Enum.map(& &1.id) == [newest.id]

    assert Bridges.list_imports_for_bridge(bridge, limit: 1)
           |> Enum.map(& &1.id) == [newest.id]
  end

  test "Scenes context supports CRUD and list ordering" do
    room = insert_room("Den")

    {:ok, scene_b} = Scenes.create_scene(%{name: "B scene", room_id: room.id})
    {:ok, scene_a} = Scenes.create_scene(%{name: "A scene", room_id: room.id})

    names = Scenes.list_scenes_for_room(room.id) |> Enum.map(& &1.name)
    assert names == ["A scene", "B scene"]

    {:ok, updated} = Scenes.update_scene(scene_a, %{name: "A2"})
    assert updated.name == "A2"

    assert {:ok, _} = Scenes.delete_scene(scene_b)
    assert Scenes.get_scene(scene_b.id) == nil
  end

  test "AppSettings.get_global returns app-config fallback when no DB row exists" do
    Repo.delete_all(AppSetting)

    previous = Application.get_env(:hueworks, :global_solar_config)

    Application.put_env(:hueworks, :global_solar_config, %{
      latitude: 41.0,
      longitude: -87.0,
      timezone: "America/Chicago"
    })

    on_exit(fn ->
      Application.put_env(:hueworks, :global_solar_config, previous)
    end)

    settings = AppSettings.get_global()

    assert settings.scope == "global"
    assert settings.latitude == 41.0
    assert settings.longitude == -87.0
    assert settings.timezone == "America/Chicago"
  end

  test "AppSettings.upsert_global inserts and updates singleton row" do
    Repo.delete_all(AppSetting)

    assert {:ok, inserted} =
             AppSettings.upsert_global(%{
               latitude: 37.7749,
               longitude: -122.4194,
               timezone: "America/Los_Angeles"
             })

    assert inserted.scope == "global"

    assert {:ok, updated} =
             AppSettings.upsert_global(%{
               latitude: 40.7128,
               longitude: -74.0060,
               timezone: "America/New_York"
             })

    assert updated.id == inserted.id
    assert updated.latitude == 40.7128
    assert updated.longitude == -74.006
    assert updated.timezone == "America/New_York"
    assert Repo.aggregate(AppSetting, :count) == 1
  end

  test "AppSettings.upsert_global validates ranges and timezone" do
    Repo.delete_all(AppSetting)
    previous = Application.get_env(:hueworks, :global_solar_config)

    Application.put_env(:hueworks, :global_solar_config, %{
      latitude: nil,
      longitude: nil,
      timezone: nil
    })

    on_exit(fn ->
      Application.put_env(:hueworks, :global_solar_config, previous)
    end)

    assert {:error, changeset} =
             AppSettings.upsert_global(%{
               latitude: 200,
               longitude: 300,
               timezone: ""
             })

    assert changeset.errors[:latitude] != nil
    assert changeset.errors[:longitude] != nil
    assert changeset.errors[:timezone] != nil
  end
end
