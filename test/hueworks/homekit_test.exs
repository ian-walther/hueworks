defmodule Hueworks.HomeKitTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.AppSettings
  alias Hueworks.Control.State
  alias Hueworks.HomeKit
  alias Hueworks.HomeKit.AccessoryGraph
  alias Hueworks.HomeKit.Bridge, as: HomeKitBridge
  alias Hueworks.HomeKit.ValueStore
  alias Hueworks.Lights
  alias Hueworks.Repo
  alias Hueworks.Schemas.{AppSetting, Bridge, Group, GroupLight, Light, Room, Scene}

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)

    :ok
  end

  test "accessory graph is disabled when no scenes or entities are exposed" do
    assert {:disabled, %{lights: [], groups: [], scenes: []}} = AccessoryGraph.build()
  end

  test "accessory graph exposes all scenes behind the global scene toggle and opt-in entities" do
    room = Repo.insert!(%Room{name: "Kitchen"})
    other_room = Repo.insert!(%Room{name: "Foyer"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        display_name: "Kitchen Task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id,
        homekit_export_mode: :switch
      })

    hidden_light =
      Repo.insert!(%Light{
        name: "kitchen.hidden",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        room_id: room.id,
        homekit_export_mode: :none
      })

    group =
      Repo.insert!(%Group{
        name: "kitchen.group",
        display_name: "Kitchen Group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        room_id: room.id,
        homekit_export_mode: :switch
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: hidden_light.id})

    scene = Repo.insert!(%Scene{name: "Dinner", room_id: room.id})
    other_scene = Repo.insert!(%Scene{name: "Welcome", room_id: other_room.id})

    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.0,
        longitude: -75.0,
        timezone: "America/New_York",
        homekit_scenes_enabled: true
      })

    assert {:ok, server, topology} = AccessoryGraph.build()

    assert Enum.map(topology.lights, & &1.id) == [light.id]
    assert Enum.map(topology.groups, & &1.id) == [group.id]
    assert Enum.map(topology.scenes, & &1.id) == [other_scene.id, scene.id]

    assert Enum.map(server.accessories, & &1.name) == [
             "Kitchen Task",
             "Kitchen Group",
             "Welcome",
             "Dinner"
           ]
  end

  test "value store reads entity power and active scene state" do
    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id
      })

    scene = Repo.insert!(%Scene{name: "Dinner", room_id: room.id})

    State.put(:light, light.id, %{power: :on})
    Hueworks.ActiveScenes.set_active(scene)

    assert ValueStore.get_value(kind: :light, id: light.id) == {:ok, true}
    assert ValueStore.get_value(kind: :scene, id: scene.id) == {:ok, true}
  end

  test "bridge restarts HAP child when exposed entity topology changes" do
    original_hap_module = Application.get_env(:hueworks, :homekit_hap_module)
    original_sink = Application.get_env(:hueworks, :homekit_test_sink)

    Application.put_env(:hueworks, :homekit_hap_module, __MODULE__.HAPStub)
    Application.put_env(:hueworks, :homekit_test_sink, self())

    on_exit(fn ->
      restore_app_env(:hueworks, :homekit_hap_module, original_hap_module)
      restore_app_env(:hueworks, :homekit_test_sink, original_sink)
    end)

    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        display_name: "Kitchen Task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id,
        homekit_export_mode: :none
      })

    start_supervised!({HomeKitBridge, []})
    refute_receive {:hap_started, _names}

    {:ok, _updated} =
      Lights.update_display_name(light, %{
        display_name: "Kitchen Task",
        homekit_export_mode: :switch
      })

    assert_receive {:hap_started, ["Kitchen Task"]}
    assert %{running?: true, topology_hash: hash} = HomeKitBridge.status()
    assert is_binary(hash)

    HomeKit.reload()
    refute_receive {:hap_started, _names}
  end

  defp insert_bridge! do
    Repo.insert!(%Bridge{
      name: "Hue Bridge",
      type: :hue,
      host: "192.168.1.2",
      credentials: %{api_key: "key"},
      enabled: true
    })
  end

  defmodule HAPStub do
    def start_link(accessory_server) do
      if sink = Application.get_env(:hueworks, :homekit_test_sink) do
        send(sink, {:hap_started, Enum.map(accessory_server.accessories, & &1.name)})
      end

      Supervisor.start_link([], strategy: :one_for_one)
    end
  end
end
