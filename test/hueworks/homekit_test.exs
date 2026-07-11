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
  alias Hueworks.HomeKit.ValueStore
  alias Hueworks.Lights
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, Bridge, Group, GroupLight, Light, Room, Scene}

  setup do
    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)

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

    original_convergence_delay =
      Application.get_env(:hueworks, :control_executor_convergence_delay_ms)

    original_homekit_data_path = Application.get_env(:hueworks, :homekit_data_path)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)
    Application.put_env(:hueworks, :control_executor_convergence_delay_ms, 10_000)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_server, original_server)

      restore_app_env(
        :hueworks,
        :control_executor_convergence_delay_ms,
        original_convergence_delay
      )

      restore_app_env(:hueworks, :homekit_data_path, original_homekit_data_path)
    end)

    {:ok, actions_agent: actions_agent, executor_server: server}
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

  test "accessory graph exposes brightness only for light export mode" do
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
        homekit_export_mode: :light
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

    assert {:ok, server, _topology} = AccessoryGraph.build()
    tree = HAP.AccessoryServer.accessories_tree(HAP.AccessoryServer.compile(server))

    [light_accessory, group_accessory] = tree.accessories

    assert "8" in characteristic_types(light_accessory)
    refute "8" in characteristic_types(group_accessory)
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

  test "value store reads and writes entity brightness", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id,
        homekit_export_mode: :light
      })

    State.put(:light, light.id, %{power: :on, brightness: 42})

    assert ValueStore.get_value(kind: :light, id: light.id, characteristic: :brightness) ==
             {:ok, 42}

    assert :ok = ValueStore.put_value(73, kind: :light, id: light.id, characteristic: :brightness)

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

  test "value store writes light power through desired-state planning", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.task",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        homekit_export_mode: :switch
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})
    _ = State.put(:light, light.id, %{power: :off})

    assert :ok = ValueStore.put_value(true, kind: :light, id: light.id)

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
    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    light_a =
      Repo.insert!(%Light{
        name: "kitchen.task.a",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id
      })

    light_b =
      Repo.insert!(%Light{
        name: "kitchen.task.b",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        room_id: room.id
      })

    group =
      Repo.insert!(%Group{
        name: "kitchen.group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        room_id: room.id,
        homekit_export_mode: :switch
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_a.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: light_b.id})

    _ = DesiredState.put(:light, light_a.id, %{power: :on})
    _ = DesiredState.put(:light, light_b.id, %{power: :on})
    _ = State.put(:light, light_a.id, %{power: :on})
    _ = State.put(:light, light_b.id, %{power: :on})

    assert :ok = ValueStore.put_value(false, kind: :group, id: group.id)

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
    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    light =
      Repo.insert!(%Light{
        name: "kitchen.scene",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, light_state} =
      Scenes.create_light_state("Warm", :manual, %{
        "brightness" => "42",
        "temperature" => "3100"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Dinner", room_id: room.id})
    {:ok, other_scene} = Scenes.create_scene(%{name: "Cleanup", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Warm", light_ids: [light.id], light_state_id: light_state.id}
      ])

    _ = State.put(:light, light.id, %{power: :off})

    assert :ok = ValueStore.put_value(true, kind: :scene, id: scene.id)

    drain_executor(executor_server)

    assert %{scene_id: active_scene_id} = ActiveScenes.get_for_room(room.id)
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
    assert ActiveScenes.get_for_room(room.id) == nil
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

    assert {:noreply, ^state, 4_321} =
             HAPSessionHandler.handle_info({:plug_conn, :sent}, state)
  end

  test "homekit HAP session handler delegates normal child exits to Bandit" do
    state = hap_session_state(4_322)

    assert {:noreply, ^state, 4_322} =
             HAPSessionHandler.handle_info({:EXIT, self(), :normal}, state)
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

    room = Repo.insert!(%Room{name: "Kitchen"})

    start_supervised!({HomeKitBridge, []})
    refute_receive {:hap_started, _names}

    assert {:ok, _scene} = Scenes.create_scene(%{name: "Dinner", room_id: room.id})
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

    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    Repo.insert!(%Light{
      name: "kitchen.task",
      display_name: "Kitchen Task",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      room_id: room.id,
      homekit_export_mode: :switch
    })

    start_supervised!({HomeKitBridge, []})

    assert_receive {:hap_started, []}
    __MODULE__.PairingStateStub.put(true)
    send(HomeKitBridge, :pairing_watchdog)

    assert_receive {:hap_started, ["Kitchen Task"]}, 200
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

    room = Repo.insert!(%Room{name: "Kitchen"})
    bridge = insert_bridge!()

    Repo.insert!(%Light{
      name: "kitchen.task",
      display_name: "Kitchen Task",
      source: :hue,
      source_id: "1",
      bridge_id: bridge.id,
      room_id: room.id,
      homekit_export_mode: :switch
    })

    start_supervised!({HomeKitBridge, []})

    assert_receive {:hap_started, ["Kitchen Task"]}
    assert_receive {:hap_started, ["Kitchen Task"]}, 200
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

    {socket, %{}}
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
