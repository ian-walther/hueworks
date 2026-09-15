defmodule Hueworks.HomeKitTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Control.{DesiredState, Executor, State}
  alias Hueworks.HomeKit
  alias Hueworks.HomeKit.AccessoryGraph
  alias Hueworks.HomeKit.Bridge, as: HomeKitBridge
  alias Hueworks.HomeKit.Config, as: HomeKitConfig
  alias Hueworks.HomeKit.HAPSessionHandler
  alias Hueworks.HomeKit.ValueCache
  alias Hueworks.HomeKit.ValueStore
  alias Hueworks.HomeKit.Writer
  alias Hueworks.Lights
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, Bridge, Group, GroupLight, Light, Area, Scene}

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    :ok = Writer.discard_pending()

    actions_id = {:homekit_executor_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      :ok
    end

    server = {:global, {:homekit_executor, self()}}

    {:ok, _pid} =
      start_supervised(
        {Executor, name: server, dispatch_fun: dispatch_fun, bridge_rate_fun: fn _ -> 10 end}
      )

    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)

    original_homekit_data_path = Application.get_env(:hueworks, :homekit_data_path)
    original_pairing_state = Application.get_env(:hueworks, :homekit_pairing_state_module)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)
    # Unless a test says otherwise, model an install that was paired before identities were
    # persisted: entities keep the positional numbering they already published.
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairedStub)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_server, original_server)
      restore_app_env(:hueworks, :homekit_pairing_state_module, original_pairing_state)

      restore_app_env(:hueworks, :homekit_data_path, original_homekit_data_path)
    end)

    {:ok, actions_agent: actions_agent, executor_server: server}
  end

  test "accessory graph is disabled when no scenes or entities are exposed" do
    assert {:disabled, %{lights: [], groups: [], scenes: []}} = AccessoryGraph.build()
  end

  test "accessory graph exposes all scenes behind the global scene toggle and opt-in entities" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    other_area = Repo.insert!(%Area{name: "Foyer"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        display_name: "Kitchen Task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :switch
      })

    hidden_light =
      Repo.insert!(%Light{
        name: "kitchen.hidden",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :none
      })

    group =
      Repo.insert!(%Group{
        name: "kitchen.group",
        display_name: "Kitchen Group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :switch
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: hidden_light.id})

    scene = Repo.insert!(%Scene{name: "Dinner", area_id: area.id})
    other_scene = Repo.insert!(%Scene{name: "Welcome", area_id: other_area.id})

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

  test "accessory graph exposes brightness only for light export mode" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        display_name: "Kitchen Task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    group =
      Repo.insert!(%Group{
        name: "kitchen.group",
        display_name: "Kitchen Group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :switch
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})

    assert {:ok, server, _topology} = AccessoryGraph.build()
    tree = HAP.AccessoryServer.accessories_tree(HAP.AccessoryServer.compile(server))

    [light_accessory, group_accessory] = tree.accessories

    assert "8" in characteristic_types(light_accessory)
    refute "8" in characteristic_types(group_accessory)
  end

  test "accessory ids stay put when an earlier-sorting light is exposed later" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    Repo.insert!(%Light{
      name: "kitchen.zeta",
      display_name: "Zeta",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :switch
    })

    assert {:ok, server, topology} = AccessoryGraph.build()
    assert Enum.map(server.accessories, & &1.name) == ["Zeta"]
    assert [%{aid: 1}] = topology.lights

    Repo.insert!(%Light{
      name: "kitchen.alpha",
      display_name: "Alpha",
      source: :hue,
      source_id: "2",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :switch
    })

    assert {:ok, server, topology} = AccessoryGraph.build()
    assert Enum.map(server.accessories, & &1.name) == ["Zeta", "Alpha"]
    assert Enum.map(topology.lights, &{&1.name, &1.aid}) == [{"Alpha", 2}, {"Zeta", 1}]
  end

  test "a fresh install reserves accessory id 1 for the bridge and numbers entities from 2" do
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairingStateStub)
    __MODULE__.PairingStateStub.put(false)
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    Repo.insert!(%Light{
      name: "kitchen.task",
      display_name: "Kitchen Task",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :switch
    })

    assert {:ok, server, %{primary_aid: 1}} = AccessoryGraph.build()
    [primary, light] = server.accessories
    assert AccessoryGraph.primary?(primary)

    assert {primary.aid, primary.name} ==
             {1, Hueworks.AppSettings.HomeKitConfig.default_bridge_name()}

    assert {light.aid, light.name} == {2, "Kitchen Task"}

    tree = HAP.AccessoryServer.accessories_tree(HAP.AccessoryServer.compile(server))
    [primary_tree, _light_tree] = tree.accessories
    # The bridge accessory carries Accessory Information and Protocol Information only.
    assert Enum.map(primary_tree.services, & &1.type) == ["3E", "A2"]

    # Pairing later does not renumber anything.
    __MODULE__.PairingStateStub.put(true)
    assert {:ok, server, _topology} = AccessoryGraph.build()
    assert Enum.map(server.accessories, & &1.aid) == [1, 2]
  end

  test "an upgraded install keeps its first entity at id 1 and gets a bridge accessory there only while it is gone" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    first =
      Repo.insert!(%Light{
        name: "kitchen.first",
        display_name: "First",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :switch
      })

    Repo.insert!(%Light{
      name: "kitchen.second",
      display_name: "Second",
      source: :hue,
      source_id: "2",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :switch
    })

    assert {:ok, server, _topology} = AccessoryGraph.build()
    assert Enum.map(server.accessories, & &1.name) == ["First", "Second"]

    first =
      first
      |> Ecto.Changeset.change(homekit_export_mode: :none)
      |> Repo.update!()

    assert {:ok, server, %{primary_aid: 1}} = AccessoryGraph.build()
    assert [primary, %{name: "Second", aid: 2}] = server.accessories
    assert AccessoryGraph.primary?(primary) and primary.aid == 1

    tree = HAP.AccessoryServer.accessories_tree(HAP.AccessoryServer.compile(server))
    assert Enum.map(tree.accessories, & &1.aid) == [1, 2]

    first
    |> Ecto.Changeset.change(homekit_export_mode: :switch)
    |> Repo.update!()

    assert {:ok, server, _topology} = AccessoryGraph.build()
    assert Enum.map(server.accessories, &{&1.name, &1.aid}) == [{"First", 1}, {"Second", 2}]
  end

  test "accessory graph exposes color and temperature by capability in light mode" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    Repo.insert!(%Light{
      name: "kitchen.color",
      display_name: "Color",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      area_id: area.id,
      supports_color: true,
      supports_temp: true,
      homekit_export_mode: :light
    })

    Repo.insert!(%Light{
      name: "kitchen.dimmer",
      display_name: "Dimmer",
      source: :hue,
      source_id: "2",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :light
    })

    Repo.insert!(%Light{
      name: "kitchen.switch",
      display_name: "Switch",
      source: :hue,
      source_id: "3",
      bridge_id: bridge.id,
      area_id: area.id,
      supports_color: true,
      supports_temp: true,
      homekit_export_mode: :switch
    })

    assert {:ok, server, _topology} = AccessoryGraph.build()
    tree = HAP.AccessoryServer.accessories_tree(HAP.AccessoryServer.compile(server))
    [color, dimmer, switch] = tree.accessories

    # 8 brightness, 13 hue, 2F saturation, CE color temperature
    assert Enum.all?(~w[8 13 2F CE], &(&1 in characteristic_types(color)))
    assert "8" in characteristic_types(dimmer)
    refute Enum.any?(~w[13 2F CE], &(&1 in characteristic_types(dimmer)))
    refute Enum.any?(~w[8 13 2F CE], &(&1 in characteristic_types(switch)))

    assert Hueworks.HomeKit.Characteristics.ColorTemperature.min_value() == 140
    assert Hueworks.HomeKit.Characteristics.ColorTemperature.max_value() == 500
  end

  test "value store reads hue and saturation from xy and mireds from kelvin" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.color",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_color: true,
        supports_temp: true,
        homekit_export_mode: :light
      })

    {x, y} = Hueworks.Color.hs_to_xy(120, 100)
    State.put(:light, light.id, %{power: :on, brightness: 50, x: x, y: y})

    assert {:ok, hue} = ValueStore.get_value(kind: :light, id: light.id, characteristic: :hue)
    assert_in_delta hue, 120.0, 2.0

    assert {:ok, saturation} =
             ValueStore.get_value(kind: :light, id: light.id, characteristic: :saturation)

    assert_in_delta saturation, 100.0, 2.0

    State.put(:light, light.id, %{kelvin: 2700})

    assert ValueStore.get_value(kind: :light, id: light.id, characteristic: :color_temperature) ==
             {:ok, 370}

    # In temperature mode the color wheel reflects the warm white (an orange hue, well
    # short of full saturation) rather than the stale green.
    assert {:ok, warm_hue} =
             ValueStore.get_value(kind: :light, id: light.id, characteristic: :hue)

    assert warm_hue > 15.0 and warm_hue < 60.0

    assert {:ok, warm_saturation} =
             ValueStore.get_value(kind: :light, id: light.id, characteristic: :saturation)

    assert warm_saturation < 90.0
  end

  test "value store applies hue and saturation as xy and mireds as clamped kelvin" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.color",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_color: true,
        supports_temp: true,
        reported_min_kelvin: 2200,
        reported_max_kelvin: 6500,
        homekit_export_mode: :light
      })

    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 50, kelvin: 3000})
    State.put(:light, light.id, %{power: :on, brightness: 50, kelvin: 3000})

    assert :ok = ValueStore.put_value(120, kind: :light, id: light.id, characteristic: :hue)

    assert :ok =
             ValueStore.put_value(100, kind: :light, id: light.id, characteristic: :saturation)

    :ok = Writer.flush()

    {x, y} = Hueworks.Color.hs_to_xy(120, 100)

    assert %{power: :on, brightness: 50, x: ^x, y: ^y} =
             desired = DesiredState.get(:light, light.id)

    refute Map.has_key?(desired, :kelvin)

    # 500 mireds is 2000 K, below this light's floor.
    assert :ok =
             ValueStore.put_value(500,
               kind: :light,
               id: light.id,
               characteristic: :color_temperature
             )

    :ok = Writer.flush()

    assert %{power: :on, brightness: 50, kelvin: 2200} =
             desired = DesiredState.get(:light, light.id)

    refute Map.has_key?(desired, :x)
  end

  test "a color temperature write cancels a pending hue and saturation" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.color",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_color: true,
        supports_temp: true,
        homekit_export_mode: :light
      })

    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 50})
    State.put(:light, light.id, %{power: :on, brightness: 50})

    assert :ok = ValueStore.put_value(200, kind: :light, id: light.id, characteristic: :hue)

    assert :ok =
             ValueStore.put_value(80, kind: :light, id: light.id, characteristic: :saturation)

    assert :ok =
             ValueStore.put_value(250,
               kind: :light,
               id: light.id,
               characteristic: :color_temperature
             )

    :ok = Writer.flush()

    assert %{power: :on, brightness: 50, kelvin: 4000} =
             desired = DesiredState.get(:light, light.id)

    refute Map.has_key?(desired, :x)
    assert ValueCache.get(:light, light.id, :hue) == :miss
    assert ValueCache.get(:light, light.id, :color_temperature) == {:ok, 250}
  end

  test "brightness zero turns the light off" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.dimmer",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 50})
    State.put(:light, light.id, %{power: :on, brightness: 50})

    assert :ok = ValueStore.put_value(0, kind: :light, id: light.id, characteristic: :brightness)
    :ok = Writer.flush()

    assert %{power: :off} = DesiredState.get(:light, light.id)
  end

  test "first-run identities reproduce the positional tree an existing install already has" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.0,
        longitude: -75.0,
        timezone: "America/New_York",
        homekit_scenes_enabled: true
      })

    # The shapes production publishes today: switch and dimmable lights, a group, scenes.
    dimmer =
      Repo.insert!(%Light{
        name: "kitchen.dimmer",
        display_name: "Dimmer",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    Repo.insert!(%Light{
      name: "kitchen.switch",
      display_name: "Switch",
      source: :hue,
      source_id: "2",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :switch
    })

    group =
      Repo.insert!(%Group{
        name: "kitchen.group",
        display_name: "Group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: dimmer.id})
    Repo.insert!(%Scene{name: "Dinner", area_id: area.id})

    assert {:ok, server, _topology} = AccessoryGraph.build()

    explicit = HAP.AccessoryServer.accessories_tree(HAP.AccessoryServer.compile(server), false)

    positional =
      server
      |> Map.update!(:accessories, fn accessories ->
        Enum.map(accessories, fn accessory ->
          %{accessory | aid: nil, services: Enum.map(accessory.services, &strip_iids/1)}
        end)
      end)
      |> HAP.AccessoryServer.compile()
      |> HAP.AccessoryServer.accessories_tree(false)

    assert explicit == positional
    assert Enum.map(explicit.accessories, & &1.aid) == [1, 2, 3, 4]

    [dimmer_tree | _rest] = explicit.accessories
    bulb = Enum.find(dimmer_tree.services, &(&1.type == "43"))
    assert bulb.iid == 1025

    assert Enum.map(bulb.characteristics, &{&1.type, &1.iid}) == [
             {"25", 1027},
             {"8", 1029},
             {"23", 1031}
           ]
  end

  test "requests route by persisted ids after a capability is removed, restored, and the graph rebuilt" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    member =
      Repo.insert!(%Light{
        name: "kitchen.member",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id
      })

    group =
      Repo.insert!(%Group{
        name: "kitchen.group",
        display_name: "Group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_color: true,
        supports_temp: true,
        homekit_export_mode: :light
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: member.id})
    State.put(:group, group.id, %{power: :on, brightness: 50, kelvin: 3000})

    compiled = compiled_server()
    %{"CE" => ct_iid, "13" => hue_iid} = characteristic_iids()["group-#{group.id}"]
    aid = 1

    assert [%{status: 0, value: 333}] =
             HAP.AccessoryServer.get_characteristics(
               compiled,
               [%{aid: aid, iid: ct_iid}],
               :pr,
               []
             )

    group = group |> Ecto.Changeset.change(supports_temp: false) |> Repo.update!()
    compiled = compiled_server()

    # The removed characteristic's id is refused rather than resolving to a neighbour.
    assert [%{status: -70_409}] =
             HAP.AccessoryServer.get_characteristics(
               compiled,
               [%{aid: aid, iid: ct_iid}],
               :pr,
               []
             )

    assert [%{status: -70_409}] =
             HAP.AccessoryServer.put_characteristics(
               compiled,
               [%{"aid" => aid, "iid" => ct_iid, "value" => 250}],
               self()
             )

    # Surviving characteristics keep their ids and still route to the right value.
    assert characteristic_iids()["group-#{group.id}"]["13"] == hue_iid

    assert [%{status: 0}] =
             HAP.AccessoryServer.put_characteristics(
               compiled,
               [%{"aid" => aid, "iid" => hue_iid, "value" => 200}],
               self()
             )

    assert ValueCache.get(:group, group.id, :hue) == {:ok, 200.0}
    :ok = Writer.discard_pending()

    _group = group |> Ecto.Changeset.change(supports_temp: true) |> Repo.update!()
    restored = characteristic_iids()["group-#{group.id}"]
    assert restored["CE"] == ct_iid
    assert restored["13"] == hue_iid

    # A rebuild from persisted state (as after a restart) publishes the same identities.
    assert characteristic_iids() == characteristic_iids()

    assert [%{status: 0, value: 333}] =
             HAP.AccessoryServer.get_characteristics(
               compiled_server(),
               [%{aid: aid, iid: ct_iid}],
               :pr,
               []
             )
  end

  test "characteristic ids stay put when an entity gains temperature or color support" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    color_only =
      Repo.insert!(%Group{
        name: "kitchen.rgb",
        display_name: "RGB",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_color: true,
        supports_temp: false,
        homekit_export_mode: :light
      })

    temp_only =
      Repo.insert!(%Group{
        name: "kitchen.white",
        display_name: "White",
        source: :hue,
        source_id: "11",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_color: false,
        supports_temp: true,
        homekit_export_mode: :light
      })

    before = characteristic_iids()

    color_only = color_only |> Ecto.Changeset.change(supports_temp: true) |> Repo.update!()
    _temp_only = temp_only |> Ecto.Changeset.change(supports_color: true) |> Repo.update!()

    after_gain = characteristic_iids()

    # Every characteristic published before keeps its ID; the gained ones are appended.
    for {serial, iids} <- before do
      assert Map.take(after_gain[serial], Map.keys(iids)) == iids
    end

    assert Map.has_key?(after_gain["group-#{color_only.id}"], "CE")
    assert Map.has_key?(after_gain["group-#{temp_only.id}"], "13")

    # A lost capability disappears and returns to its old slot when it comes back.
    color_only = color_only |> Ecto.Changeset.change(supports_temp: false) |> Repo.update!()
    rgb_serial = "group-#{color_only.id}"
    without_temp = characteristic_iids()
    refute Map.has_key?(without_temp[rgb_serial], "CE")

    assert Map.take(after_gain[rgb_serial], ["13", "2F"]) ==
             Map.take(without_temp[rgb_serial], ["13", "2F"])

    _color_only = color_only |> Ecto.Changeset.change(supports_temp: true) |> Repo.update!()
    assert characteristic_iids() == after_gain
  end

  test "value store reads entity power and active scene state" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id
      })

    scene = Repo.insert!(%Scene{name: "Dinner", area_id: area.id})

    State.put(:light, light.id, %{power: :on})
    Hueworks.ActiveScenes.set_active(scene)

    assert ValueStore.get_value(kind: :light, id: light.id) == {:ok, true}
    assert ValueStore.get_value(kind: :scene, id: scene.id) == {:ok, true}
  end

  test "value store reads and writes entity brightness", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    State.put(:light, light.id, %{power: :on, brightness: 42})

    assert ValueStore.get_value(kind: :light, id: light.id, characteristic: :brightness) ==
             {:ok, 42}

    assert :ok = ValueStore.put_value(73, kind: :light, id: light.id, characteristic: :brightness)

    :ok = Writer.flush()
    drain_executor(executor_server)

    assert [
             %{
               type: :light,
               id: light_id,
               desired: %{brightness: 73}
             }
           ] = Agent.get(actions_agent, & &1)

    assert light_id == light.id
  end

  test "homekit level writes use the short HomeKit transition", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    State.put(:light, light.id, %{power: :on, brightness: 42})

    assert :ok = ValueStore.put_value(73, kind: :light, id: light.id, characteristic: :brightness)
    :ok = Writer.flush()
    drain_executor(executor_server)

    assert [%{desired: %{brightness: 73}, apply_opts: %{transition_ms: 100}}] =
             Agent.get(actions_agent, & &1)
  end

  test "value store writes light power through desired-state planning", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        homekit_export_mode: :switch
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok = ValueStore.put_value(true, kind: :light, id: light.id)

    :ok = Writer.flush()
    drain_executor(executor_server)

    assert [
             %{
               type: :light,
               id: light_id,
               desired: %{power: :on, brightness: 100, kelvin: 3000}
             }
           ] = Agent.get(actions_agent, & &1)

    assert light_id == light.id
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 100, kelvin: 3000}
  end

  test "value store writes group power through desired-state planning", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light_a =
      Repo.insert!(%Light{
        name: "kitchen.task.a",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id
      })

    light_b =
      Repo.insert!(%Light{
        name: "kitchen.task.b",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        area_id: area.id
      })

    group =
      Repo.insert!(%Group{
        name: "kitchen.group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :switch
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    _ = DesiredState.put(:light, light_a.id, %{power: :on})
    _ = DesiredState.put(:light, light_b.id, %{power: :on})
    _ = State.put(:light, light_a.id, %{power: :on})
    _ = State.put(:light, light_b.id, %{power: :on})

    assert :ok = ValueStore.put_value(false, kind: :group, id: group.id)

    :ok = Writer.flush()
    drain_executor(executor_server)

    assert [
             %{
               type: :group,
               id: group_id,
               desired: %{power: :off}
             }
           ] = Agent.get(actions_agent, & &1)

    assert group_id == group.id
    assert DesiredState.get(:light, light_a.id) == %{power: :off}
    assert DesiredState.get(:light, light_b.id) == %{power: :off}
  end

  test "value store scene switch activates and deactivates HueWorks scenes", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.scene",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, light_state} =
      Scenes.create_light_state("Warm", :manual, %{
        "brightness" => "42",
        "temperature" => "3100"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Dinner", area_id: area.id})
    {:ok, other_scene} = Scenes.create_scene(%{name: "Cleanup", area_id: area.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Warm", light_ids: [light.id], light_state_id: light_state.id}
      ])

    _ = State.put(:light, light.id, %{power: :off})

    assert :ok = ValueStore.put_value(true, kind: :scene, id: scene.id)

    :ok = Writer.flush()
    drain_executor(executor_server)

    assert %{scene_id: active_scene_id} = ActiveScenes.get_for_area(area.id)
    assert active_scene_id == scene.id
    assert ValueStore.get_value(kind: :scene, id: scene.id) == {:ok, true}
    assert ValueStore.get_value(kind: :scene, id: other_scene.id) == {:ok, false}

    assert [
             %{
               type: :light,
               id: light_id,
               desired: %{power: :on, brightness: 42, kelvin: 3100}
             }
           ] = Agent.get(actions_agent, & &1)

    assert light_id == light.id

    assert :ok = ValueStore.put_value(false, kind: :scene, id: scene.id)
    :ok = Writer.flush()
    assert ActiveScenes.get_for_area(area.id) == nil
    assert ValueStore.get_value(kind: :scene, id: scene.id) == {:ok, false}
  end

  test "homekit config honors the persistent data path runtime setting" do
    Application.put_env(:hueworks, :homekit_data_path, "/data/homekit")

    config =
      %AppSetting{scope: "global"}
      |> HomeKitConfig.from_settings()

    assert config.data_path == "/data/homekit"
  end

  test "hueworks HAP runtime uses configured static networking" do
    original_port = Application.get_env(:hueworks, :homekit_port)
    original_mdns_host = Application.get_env(:hueworks, :homekit_mdns_host)

    Application.put_env(:hueworks, :homekit_port, 52_127)
    Application.put_env(:hueworks, :homekit_mdns_host, "hueworks")

    on_exit(fn ->
      restore_app_env(:hueworks, :homekit_port, original_port)
      restore_app_env(:hueworks, :homekit_mdns_host, original_mdns_host)
    end)

    assert Hueworks.HomeKit.HAP.port() == 52_127
    assert Hueworks.HomeKit.HAP.mdns_host() == "hueworks"

    bandit_child =
      %HAP.AccessoryServer{name: "Test", identifier: "02:00:00:00:00:01"}
      |> Hueworks.HomeKit.HAP.child_specs()
      |> Enum.find(fn
        {Bandit, _opts} -> true
        _ -> false
      end)

    assert {Bandit, bandit_opts} = bandit_child
    assert bandit_opts[:port] == 52_127
    assert bandit_opts[:ip] == {0, 0, 0, 0}

    transport_opts = bandit_opts[:thousand_island_options]
    assert transport_opts[:handler_module] == Hueworks.HomeKit.HAPSessionHandler
    assert transport_opts[:transport_module] == Hueworks.HomeKit.HAPSessionTransport
    assert transport_opts[:read_timeout] == :infinity
  end

  test "homekit transport chunks encrypted responses into HAP-sized frames" do
    key = <<1::256>>
    payload = :binary.copy("a", 2_050)

    Process.delete(:send_counter)
    frames = Hueworks.HomeKit.HAPSessionTransport.encrypted_frames(payload, key)

    assert encrypted_frame_lengths(IO.iodata_to_binary(frames)) == [1_024, 1_024, 2]
    assert Process.get(:send_counter) == 3

    Process.delete(:recv_counter)
    Process.put(:hap_recv_key, key)

    assert {:ok, ^payload} =
             frames
             |> IO.iodata_to_binary()
             |> Hueworks.HomeKit.HAPSessionTransport.decrypt_if_needed()
  end

  test "homekit HAP session handler delegates sent notifications to Bandit" do
    state = hap_session_state(4_321)

    assert {:noreply, ^state} = HAPSessionHandler.handle_info({:plug_conn, :sent}, state)
  end

  test "homekit HAP session handler delegates normal child exits to Bandit" do
    state = hap_session_state(4_322)

    assert {:noreply, ^state} = HAPSessionHandler.handle_info({:EXIT, self(), :normal}, state)
  end

  test "bridge restarts HAP child when exposed entity topology changes" do
    original_hap_module = Application.get_env(:hueworks, :homekit_hap_module)
    original_pairing_state_module = Application.get_env(:hueworks, :homekit_pairing_state_module)
    original_sink = Application.get_env(:hueworks, :homekit_test_sink)

    Application.put_env(:hueworks, :homekit_hap_module, __MODULE__.HAPStub)
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairedStub)
    Application.put_env(:hueworks, :homekit_test_sink, self())

    on_exit(fn ->
      restore_app_env(:hueworks, :homekit_hap_module, original_hap_module)
      restore_app_env(:hueworks, :homekit_pairing_state_module, original_pairing_state_module)
      restore_app_env(:hueworks, :homekit_test_sink, original_sink)
    end)

    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        display_name: "Kitchen Task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
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

  test "bridge reloads from scene domain events when scene exposure is enabled" do
    original_hap_module = Application.get_env(:hueworks, :homekit_hap_module)
    original_pairing_state_module = Application.get_env(:hueworks, :homekit_pairing_state_module)
    original_sink = Application.get_env(:hueworks, :homekit_test_sink)

    Application.put_env(:hueworks, :homekit_hap_module, __MODULE__.HAPStub)
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairedStub)
    Application.put_env(:hueworks, :homekit_test_sink, self())

    on_exit(fn ->
      restore_app_env(:hueworks, :homekit_hap_module, original_hap_module)
      restore_app_env(:hueworks, :homekit_pairing_state_module, original_pairing_state_module)
      restore_app_env(:hueworks, :homekit_test_sink, original_sink)
    end)

    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 40.0,
        longitude: -75.0,
        timezone: "America/New_York",
        homekit_scenes_enabled: true
      })

    area = Repo.insert!(%Area{name: "Kitchen"})

    start_supervised!({HomeKitBridge, []})
    refute_receive {:hap_started, _names}

    assert {:ok, _scene} = Scenes.create_scene(%{name: "Dinner", area_id: area.id})
    assert_receive {:hap_started, ["Dinner"]}
  end

  test "bridge defers child accessories until after HomeKit pairing completes" do
    original_hap_module = Application.get_env(:hueworks, :homekit_hap_module)
    original_pairing_state_module = Application.get_env(:hueworks, :homekit_pairing_state_module)

    original_publish_delay =
      Application.get_env(:hueworks, :homekit_publish_after_pairing_delay_ms)

    original_stub_paired = Application.get_env(:hueworks, :homekit_pairing_state_stub_paired?)
    original_sink = Application.get_env(:hueworks, :homekit_test_sink)

    Application.put_env(:hueworks, :homekit_hap_module, __MODULE__.HAPStub)
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairingStateStub)
    Application.put_env(:hueworks, :homekit_publish_after_pairing_delay_ms, 0)
    Application.put_env(:hueworks, :homekit_test_sink, self())
    __MODULE__.PairingStateStub.put(false)

    on_exit(fn ->
      restore_app_env(:hueworks, :homekit_hap_module, original_hap_module)
      restore_app_env(:hueworks, :homekit_pairing_state_module, original_pairing_state_module)
      restore_app_env(:hueworks, :homekit_publish_after_pairing_delay_ms, original_publish_delay)
      restore_app_env(:hueworks, :homekit_pairing_state_stub_paired?, original_stub_paired)
      restore_app_env(:hueworks, :homekit_test_sink, original_sink)
    end)

    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    Repo.insert!(%Light{
      name: "kitchen.task",
      display_name: "Kitchen Task",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :switch
    })

    start_supervised!({HomeKitBridge, []})

    # Only the bridge accessory itself is published until pairing completes.
    bridge_name = Hueworks.AppSettings.HomeKitConfig.default_bridge_name()
    assert_receive {:hap_started, [^bridge_name]}
    __MODULE__.PairingStateStub.put(true)
    send(HomeKitBridge, :pairing_watchdog)

    assert_receive {:hap_started, [^bridge_name, "Kitchen Task"]}, 200
  end

  test "bridge restarts HAP child when pair setup is stuck mid-flow" do
    original_hap_module = Application.get_env(:hueworks, :homekit_hap_module)
    original_pair_setup_module = Application.get_env(:hueworks, :homekit_pair_setup_module)
    original_pairing_state_module = Application.get_env(:hueworks, :homekit_pairing_state_module)
    original_timeout = Application.get_env(:hueworks, :homekit_pairing_timeout_ms)
    original_interval = Application.get_env(:hueworks, :homekit_pairing_watchdog_interval_ms)
    original_sink = Application.get_env(:hueworks, :homekit_test_sink)

    Application.put_env(:hueworks, :homekit_hap_module, __MODULE__.HAPStub)
    Application.put_env(:hueworks, :homekit_pair_setup_module, __MODULE__.PairSetupStuckStub)
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairedStub)
    Application.put_env(:hueworks, :homekit_pairing_timeout_ms, 0)
    Application.put_env(:hueworks, :homekit_pairing_watchdog_interval_ms, 10)
    Application.put_env(:hueworks, :homekit_test_sink, self())

    on_exit(fn ->
      restore_app_env(:hueworks, :homekit_hap_module, original_hap_module)
      restore_app_env(:hueworks, :homekit_pair_setup_module, original_pair_setup_module)
      restore_app_env(:hueworks, :homekit_pairing_state_module, original_pairing_state_module)
      restore_app_env(:hueworks, :homekit_pairing_timeout_ms, original_timeout)
      restore_app_env(:hueworks, :homekit_pairing_watchdog_interval_ms, original_interval)
      restore_app_env(:hueworks, :homekit_test_sink, original_sink)
    end)

    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    Repo.insert!(%Light{
      name: "kitchen.task",
      display_name: "Kitchen Task",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :switch
    })

    start_supervised!({HomeKitBridge, []})

    assert_receive {:hap_started, ["Kitchen Task"]}
    assert_receive {:hap_started, ["Kitchen Task"]}, 200
  end

  test "value store returns integer HAP status codes on failures" do
    assert {:error, status} = ValueStore.put_value(true, kind: :light, id: 999_999)
    assert is_integer(status)

    assert {:error, status} =
             ValueStore.get_value(kind: :light, id: 999_999, characteristic: :sparkle)

    assert is_integer(status)

    assert {:error, status} = ValueStore.put_value("bright", kind: :light, id: 999_999)
    assert is_integer(status)
  end

  test "value store rejects brightness with a HAP status while a scene is active", %{
    actions_agent: actions_agent
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    scene = Repo.insert!(%Scene{name: "Dinner", area_id: area.id})
    ActiveScenes.set_active(scene)
    State.put(:light, light.id, %{power: :on, brightness: 42})

    assert {:error, status} =
             ValueStore.put_value(50, kind: :light, id: light.id, characteristic: :brightness)

    assert is_integer(status)

    :ok = Writer.flush()
    assert Agent.get(actions_agent, & &1) == []

    assert ValueStore.get_value(kind: :light, id: light.id, characteristic: :brightness) ==
             {:ok, 42}
  end

  test "value store coalesces on and brightness into one desired-state write", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        homekit_export_mode: :light
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok = ValueStore.put_value(true, kind: :light, id: light.id, characteristic: :on)
    assert :ok = ValueStore.put_value(73, kind: :light, id: light.id, characteristic: :brightness)

    :ok = Writer.flush()
    drain_executor(executor_server)

    assert [
             %{
               type: :light,
               id: light_id,
               desired: %{power: :on, brightness: 73, kelvin: 3000}
             }
           ] = Agent.get(actions_agent, & &1)

    assert light_id == light.id
  end

  test "value store answers reads with the last HomeKit write until the bridge confirms it" do
    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    State.put(:light, light.id, %{power: :on, brightness: 42})

    assert :ok = ValueStore.put_value(73, kind: :light, id: light.id, characteristic: :brightness)

    assert ValueStore.get_value(kind: :light, id: light.id, characteristic: :brightness) ==
             {:ok, 73}

    ValueCache.reconcile(:light, light.id, %{power: :on, brightness: 60})

    assert ValueStore.get_value(kind: :light, id: light.id, characteristic: :brightness) ==
             {:ok, 73}

    State.put(:light, light.id, %{power: :on, brightness: 73})
    ValueCache.reconcile(:light, light.id, %{power: :on, brightness: 73})

    assert ValueCache.get(:light, light.id, :brightness) == :miss

    assert ValueStore.get_value(kind: :light, id: light.id, characteristic: :brightness) ==
             {:ok, 73}

    :ok = Writer.discard_pending()
  end

  test "homekit transport reassembles encrypted frames split across reads" do
    key = <<2::256>>
    payload = "hello homekit"

    Process.delete(:send_counter)

    frame =
      key
      |> then(&Hueworks.HomeKit.HAPSessionTransport.encrypted_frames(payload, &1))
      |> IO.iodata_to_binary()

    <<first::binary-size(7), second::binary>> = frame

    Process.delete(:recv_counter)
    Process.delete(:hap_recv_buffer)
    Process.put(:hap_recv_key, key)

    assert {:ok, <<>>} = Hueworks.HomeKit.HAPSessionTransport.decrypt_buffered(first)
    assert {:ok, ^payload} = Hueworks.HomeKit.HAPSessionTransport.decrypt_buffered(second)
    assert Process.get(:hap_recv_buffer, <<>>) == <<>>
  after
    Process.delete(:hap_recv_key)
    Process.delete(:hap_recv_buffer)
    Process.delete(:recv_counter)
  end

  test "homekit HAP session handler waits for the rest of a partial encrypted frame" do
    key = <<3::256>>
    {socket, state} = hap_session_state(4_323)

    Process.delete(:send_counter)

    frame =
      key
      |> then(
        &Hueworks.HomeKit.HAPSessionTransport.encrypted_frames("GET / HTTP/1.1\r\n\r\n", &1)
      )
      |> IO.iodata_to_binary()

    <<first::binary-size(5), _rest::binary>> = frame

    Process.delete(:recv_counter)
    Process.delete(:hap_recv_buffer)
    Process.put(:hap_recv_key, key)

    assert {:continue, ^state} = HAPSessionHandler.handle_data(first, socket, state)
  after
    Process.delete(:hap_recv_key)
    Process.delete(:hap_recv_buffer)
    Process.delete(:recv_counter)
  end

  test "homekit HAP session handler ignores unknown messages" do
    state = hap_session_state(4_324)

    assert {:noreply, ^state} = HAPSessionHandler.handle_info(:unexpected_message, state)
  end

  test "bridge notifies HomeKit once per changed value and skips unchanged echoes" do
    original_hap_module = Application.get_env(:hueworks, :homekit_hap_module)
    original_pairing_state_module = Application.get_env(:hueworks, :homekit_pairing_state_module)
    original_notifier = Application.get_env(:hueworks, :homekit_notifier_module)
    original_debounce = Application.get_env(:hueworks, :homekit_notify_debounce_ms)
    original_sink = Application.get_env(:hueworks, :homekit_test_sink)

    Application.put_env(:hueworks, :homekit_hap_module, __MODULE__.HAPStub)
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairedStub)
    Application.put_env(:hueworks, :homekit_notifier_module, __MODULE__.NotifierStub)
    Application.put_env(:hueworks, :homekit_notify_debounce_ms, 0)
    Application.put_env(:hueworks, :homekit_test_sink, self())

    on_exit(fn ->
      restore_app_env(:hueworks, :homekit_hap_module, original_hap_module)
      restore_app_env(:hueworks, :homekit_pairing_state_module, original_pairing_state_module)
      restore_app_env(:hueworks, :homekit_notifier_module, original_notifier)
      restore_app_env(:hueworks, :homekit_notify_debounce_ms, original_debounce)
      restore_app_env(:hueworks, :homekit_test_sink, original_sink)
    end)

    area = Repo.insert!(%Area{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        display_name: "Kitchen Task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    State.put(:light, light.id, %{power: :on, brightness: 42})

    start_supervised!({HomeKitBridge, []})
    assert_receive {:hap_started, ["Kitchen Task"]}

    HomeKit.put_change_token([kind: :light, id: light.id, characteristic: :brightness], {1, 9})
    HomeKit.put_change_token([kind: :light, id: light.id, characteristic: :on], {1, 8})
    _ = :sys.get_state(HomeKitBridge)

    State.put(:light, light.id, %{brightness: 42})
    refute_receive {:value_changed, _token}, 50

    State.put(:light, light.id, %{brightness: 50})
    assert_receive {:value_changed, {1, 9}}, 200
    refute_receive {:value_changed, {1, 8}}, 50

    State.put(:light, light.id, %{brightness: 50})
    refute_receive {:value_changed, _token}, 50

    State.put(:light, light.id, %{power: :off})
    assert_receive {:value_changed, {1, 8}}, 200
    refute_receive {:value_changed, {1, 9}}, 50
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

  defp hap_session_state(read_timeout) do
    socket = %ThousandIsland.Socket{
      socket: :test_socket,
      transport_module: __MODULE__.Transport,
      read_timeout: read_timeout,
      silent_terminate_on_error: false,
      span: nil
    }

    {socket, %{opts: %{http_1: []}}}
  end

  defp drain_executor(server, attempts \\ 5)

  defp drain_executor(_server, 0), do: :ok

  defp drain_executor(server, attempts) do
    stats = Executor.stats(server)
    queues = Map.values(stats.queues)

    if Enum.all?(queues, &(&1 == 0)) do
      :ok
    else
      Executor.tick(server, force: true)
      drain_executor(server, attempts - 1)
    end
  end

  defp compiled_server do
    {:ok, server, _topology} = AccessoryGraph.build()
    HAP.AccessoryServer.compile(server)
  end

  defp characteristic_iids do
    {:ok, server, _topology} = AccessoryGraph.build()
    tree = HAP.AccessoryServer.accessories_tree(HAP.AccessoryServer.compile(server), false)

    Map.new(tree.accessories, fn accessory ->
      bulb = Enum.find(accessory.services, &(&1.type == "43"))
      serial = Enum.find(server.accessories, &(&1.aid == accessory.aid)).serial_number
      {serial, Map.new(bulb.characteristics, &{&1.type, &1.iid})}
    end)
  end

  defp strip_iids(%Hueworks.HomeKit.LightBulbService{} = service), do: %{service | iids: nil}
  defp strip_iids(service), do: service

  defp characteristic_types(accessory) do
    accessory.services
    |> Enum.flat_map(& &1.characteristics)
    |> Enum.map(& &1.type)
  end

  defp encrypted_frame_lengths(data, lengths \\ [])

  defp encrypted_frame_lengths(<<>>, lengths), do: Enum.reverse(lengths)

  defp encrypted_frame_lengths(
         <<length::integer-size(16)-little, _encrypted::binary-size(length),
           _tag::binary-size(16), rest::binary>>,
         lengths
       ) do
    encrypted_frame_lengths(rest, [length | lengths])
  end

  defmodule HAPStub do
    def start_link(accessory_server) do
      if sink = Application.get_env(:hueworks, :homekit_test_sink) do
        send(sink, {:hap_started, Enum.map(accessory_server.accessories, & &1.name)})
      end

      Supervisor.start_link([], strategy: :one_for_one)
    end
  end

  defmodule PairSetupStuckStub do
    def state, do: %{step: 3}
  end

  defmodule NotifierStub do
    def value_changed(token) do
      if sink = Application.get_env(:hueworks, :homekit_test_sink) do
        send(sink, {:value_changed, token})
      end

      :ok
    end
  end

  defmodule PairedStub do
    def paired?(_data_path), do: true
  end

  defmodule PairingStateStub do
    def put(paired?) do
      Application.put_env(:hueworks, :homekit_pairing_state_stub_paired?, paired?)
    end

    def paired?(_data_path) do
      Application.get_env(:hueworks, :homekit_pairing_state_stub_paired?, false)
    end
  end
end
