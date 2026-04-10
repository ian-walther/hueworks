defmodule Hueworks.HomeAssistant.ExportTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.HomeAssistant.Export
  alias Hueworks.Repo
  alias Hueworks.Schemas.{AppSetting, Room, Scene}

  setup do
    original_tortoise = Application.get_env(:hueworks, :ha_export_tortoise_module)
    original_supervisor = Application.get_env(:hueworks, :ha_export_tortoise_supervisor_module)

    original_dynamic_supervisor =
      Application.get_env(:hueworks, :ha_export_dynamic_supervisor_module)

    original_supervisor_name = Application.get_env(:hueworks, :ha_export_tortoise_supervisor_name)
    original_sink = Application.get_env(:hueworks, :ha_export_publish_sink)

    Application.put_env(:hueworks, :ha_export_tortoise_module, __MODULE__.TortoiseStub)

    Application.put_env(
      :hueworks,
      :ha_export_tortoise_supervisor_module,
      __MODULE__.SupervisorStub
    )

    Application.put_env(
      :hueworks,
      :ha_export_dynamic_supervisor_module,
      __MODULE__.DynamicSupervisorStub
    )

    Application.put_env(:hueworks, :ha_export_tortoise_supervisor_name, __MODULE__.SupervisorStub)
    Application.put_env(:hueworks, :ha_export_publish_sink, self())

    Repo.delete_all(AppSetting)
    HueworksApp.Cache.flush_namespace(:app_settings)
    start_supervised!({Export, []})
    Export.reload()
    _ = :sys.get_state(Export)

    on_exit(fn ->
      Application.put_env(:hueworks, :ha_export_tortoise_module, original_tortoise)
      Application.put_env(:hueworks, :ha_export_tortoise_supervisor_module, original_supervisor)

      Application.put_env(
        :hueworks,
        :ha_export_dynamic_supervisor_module,
        original_dynamic_supervisor
      )

      Application.put_env(
        :hueworks,
        :ha_export_tortoise_supervisor_name,
        original_supervisor_name
      )

      Application.put_env(:hueworks, :ha_export_publish_sink, original_sink)
    end)

    :ok
  end

  test "discovery payload uses stable IDs and scene-only entity names" do
    room = Repo.insert!(%Room{name: "Main Floor"})
    scene = Repo.insert!(%Scene{name: "All Auto", room_id: room.id}) |> Repo.preload(:room)

    payload = Export.discovery_payload(scene)

    assert payload["name"] == "All Auto"
    assert payload["unique_id"] == "hueworks_scene_#{scene.id}"
    assert payload["command_topic"] == "hueworks/ha_export/scenes/#{scene.id}/set"
    assert payload["json_attributes_topic"] == "hueworks/ha_export/scenes/#{scene.id}/attributes"
    assert payload["device"]["identifiers"] == ["hueworks_room_#{room.id}"]
    assert payload["device"]["name"] == "HueWorks Main Floor"
  end

  test "room select discovery payload uses stable IDs and disambiguated options" do
    room = Repo.insert!(%Room{name: "Main Floor"})

    scene_a = Repo.insert!(%Scene{name: "All Auto", room_id: room.id}) |> Repo.preload(:room)
    scene_b = Repo.insert!(%Scene{name: "All Auto", room_id: room.id}) |> Repo.preload(:room)

    payload = Export.room_select_discovery_payload(room, [scene_a, scene_b])

    assert payload["name"] == "Scene"
    assert payload["unique_id"] == "hueworks_room_scene_select_#{room.id}"
    assert payload["command_topic"] == "hueworks/ha_export/rooms/#{room.id}/scene/set"
    assert payload["state_topic"] == "hueworks/ha_export/rooms/#{room.id}/scene/state"
    assert payload["device"]["name"] == "HueWorks Main Floor"
    assert payload["options"] == ["All Auto (##{scene_a.id})", "All Auto (##{scene_b.id})"]
  end

  test "publishes retained discovery and attributes payloads when connected" do
    put_export_settings(%{
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: true,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_mqtt_port: 1883,
      ha_export_discovery_prefix: "homeassistant"
    })

    room = Repo.insert!(%Room{name: "Main Floor"})
    scene = Repo.insert!(%Scene{name: "All Auto", room_id: room.id})

    Export.reload()
    _ = :sys.get_state(Export)
    send(Export, {:mqtt_connected, Export.client_id()})
    _ = :sys.get_state(Export)

    {client_id, _topic, _payload} =
      assert_publish("hueworks/ha_export/status", fn payload -> payload == "online" end)

    assert client_id == Export.client_id()

    {_client_id, _topic, payload} =
      assert_publish("homeassistant/scene/hueworks_scene_#{scene.id}/config")

    decoded = Jason.decode!(payload)
    assert decoded["name"] == "All Auto"
    assert decoded["command_topic"] == "hueworks/ha_export/scenes/#{scene.id}/set"

    {_client_id, _attrs_topic, attrs_payload} =
      assert_publish("hueworks/ha_export/scenes/#{scene.id}/attributes")

    attrs = Jason.decode!(attrs_payload)
    assert attrs["hueworks_managed"] == true
    assert attrs["hueworks_scene_id"] == scene.id

    {_client_id, _topic, select_payload} =
      assert_publish("homeassistant/select/hueworks_room_scene_select_#{room.id}/config")

    select = Jason.decode!(select_payload)
    assert select["name"] == "Scene"
    assert select["options"] == ["All Auto"]

    {_client_id, _topic, _attrs_payload} =
      assert_publish("hueworks/ha_export/rooms/#{room.id}/scene/attributes")

    {_client_id, _topic, select_state} =
      assert_publish("hueworks/ha_export/rooms/#{room.id}/scene/state")

    assert select_state == "None"
  end

  test "command topic ON activates the matching HueWorks scene" do
    put_export_settings(%{
      ha_export_scenes_enabled: true,
      ha_export_mqtt_host: "mqtt.local"
    })

    room = Repo.insert!(%Room{name: "Kitchen"})
    scene = Repo.insert!(%Scene{name: "Cooking", room_id: room.id, metadata: %{}})

    Export.reload()
    _ = :sys.get_state(Export)

    send(
      Export,
      {:mqtt_message, ["hueworks", "ha_export", "scenes", Integer.to_string(scene.id), "set"],
       "ON"}
    )

    _ = :sys.get_state(Export)

    assert %Hueworks.Schemas.ActiveScene{scene_id: scene_id} = ActiveScenes.get_for_room(room.id)
    assert scene_id == scene.id
  end

  test "room select command activates the matching HueWorks scene" do
    put_export_settings(%{
      ha_export_room_selects_enabled: true,
      ha_export_mqtt_host: "mqtt.local"
    })

    room = Repo.insert!(%Room{name: "Main Floor"})
    morning = Repo.insert!(%Scene{name: "Morning", room_id: room.id})
    evening = Repo.insert!(%Scene{name: "Evening", room_id: room.id})

    Export.reload()
    _ = :sys.get_state(Export)

    send(
      Export,
      {:mqtt_message,
       ["hueworks", "ha_export", "rooms", Integer.to_string(room.id), "scene", "set"], "Evening"}
    )

    _ = :sys.get_state(Export)

    assert %Hueworks.Schemas.ActiveScene{scene_id: scene_id} = ActiveScenes.get_for_room(room.id)
    assert scene_id == evening.id
    refute scene_id == morning.id
  end

  test "active scene updates republish the room select state" do
    put_export_settings(%{
      ha_export_room_selects_enabled: true,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_mqtt_port: 1883,
      ha_export_discovery_prefix: "homeassistant"
    })

    room = Repo.insert!(%Room{name: "Main Floor"})
    scene = Repo.insert!(%Scene{name: "All Auto", room_id: room.id})

    Export.reload()
    _ = :sys.get_state(Export)
    send(Export, {:mqtt_connected, Export.client_id()})
    _ = :sys.get_state(Export)

    drain_published_messages()

    _ = ActiveScenes.set_active(scene)

    {_client_id, _topic, state_payload} =
      assert_publish("hueworks/ha_export/rooms/#{room.id}/scene/state")

    assert state_payload == "All Auto"
  end

  test "disabling scene export unpublishes only scene entities" do
    put_export_settings(%{
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: true,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_discovery_prefix: "homeassistant"
    })

    room = Repo.insert!(%Room{name: "Main Floor"})
    scene = Repo.insert!(%Scene{name: "All Auto", room_id: room.id})

    Export.reload()
    _ = :sys.get_state(Export)
    send(Export, {:mqtt_connected, Export.client_id()})
    _ = :sys.get_state(Export)

    drain_published_messages()

    put_export_settings(%{
      ha_export_scenes_enabled: false,
      ha_export_room_selects_enabled: true,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_discovery_prefix: "homeassistant"
    })

    Export.reload()
    _ = :sys.get_state(Export)

    {_client_id, _topic, discovery_payload} =
      assert_publish("homeassistant/scene/hueworks_scene_#{scene.id}/config")

    assert discovery_payload == ""

    {_client_id, _topic, attributes_payload} =
      assert_publish("hueworks/ha_export/scenes/#{scene.id}/attributes")

    assert attributes_payload == ""

    room_select_topic = "homeassistant/select/hueworks_room_scene_select_#{room.id}/config"

    refute_received {:published, _, ^room_select_topic, "", _}
  end

  test "disabling room select export unpublishes only room select entities" do
    put_export_settings(%{
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: true,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_discovery_prefix: "homeassistant"
    })

    room = Repo.insert!(%Room{name: "Main Floor"})
    _scene = Repo.insert!(%Scene{name: "All Auto", room_id: room.id})

    Export.reload()
    _ = :sys.get_state(Export)
    send(Export, {:mqtt_connected, Export.client_id()})
    _ = :sys.get_state(Export)

    drain_published_messages()

    put_export_settings(%{
      ha_export_scenes_enabled: true,
      ha_export_room_selects_enabled: false,
      ha_export_mqtt_host: "mqtt.local",
      ha_export_discovery_prefix: "homeassistant"
    })

    Export.reload()
    _ = :sys.get_state(Export)

    {_client_id, _topic, discovery_payload} =
      assert_publish("homeassistant/select/hueworks_room_scene_select_#{room.id}/config")

    assert discovery_payload == ""

    {_client_id, _topic, attributes_payload} =
      assert_publish("hueworks/ha_export/rooms/#{room.id}/scene/attributes")

    assert attributes_payload == ""

    {_client_id, _topic, state_payload} =
      assert_publish("hueworks/ha_export/rooms/#{room.id}/scene/state")

    assert state_payload == "None"
  end

  test "command_scene_id parses scene ids from export topics" do
    assert Export.command_scene_id("hueworks/ha_export/scenes/42/set") == 42
    assert Export.command_scene_id(["hueworks", "ha_export", "scenes", "42", "set"]) == 42
    assert Export.command_scene_id("hueworks/ha_export/scenes/not-a-number/set") == nil
    assert Export.command_scene_id("hueworks/ha_export/other/42/set") == nil
  end

  test "command_room_id parses room ids from room select topics" do
    assert Export.command_room_id("hueworks/ha_export/rooms/42/scene/set") == 42
    assert Export.command_room_id(["hueworks", "ha_export", "rooms", "42", "scene", "set"]) == 42
    assert Export.command_room_id("hueworks/ha_export/rooms/not-a-number/scene/set") == nil
    assert Export.command_room_id("hueworks/ha_export/scenes/42/set") == nil
  end

  defp put_export_settings(attrs) do
    {:ok, _settings} =
      AppSettings.upsert_global(
        Map.merge(
          %{
            latitude: 40.7128,
            longitude: -74.006,
            timezone: "America/New_York",
            ha_export_scenes_enabled: false,
            ha_export_room_selects_enabled: false,
            ha_export_discovery_prefix: "homeassistant"
          },
          attrs
        )
      )

    HueworksApp.Cache.flush_namespace(:app_settings)
  end

  defp assert_publish(topic, payload_matcher \\ fn _payload -> true end) do
    receive do
      {:published, client_id, ^topic, payload, [qos: 0, retain: true]}
      when is_function(payload_matcher, 1) ->
        if payload_matcher.(payload) do
          {client_id, topic, payload}
        else
          assert_publish(topic, payload_matcher)
        end

      {:published, _client_id, _other_topic, _payload, _opts} ->
        assert_publish(topic, payload_matcher)
    after
      1_000 ->
        flunk("expected retained publish for #{topic}")
    end
  end

  defp drain_published_messages do
    receive do
      {:published, _client_id, _topic, _payload, _opts} ->
        drain_published_messages()
    after
      0 ->
        :ok
    end
  end

  defmodule TortoiseStub do
    def publish(client_id, topic, payload, opts) do
      send(
        Application.fetch_env!(:hueworks, :ha_export_publish_sink),
        {:published, client_id, topic, payload, opts}
      )

      :ok
    end
  end

  defmodule SupervisorStub do
    def start_child(_opts) do
      {:ok,
       spawn(fn ->
         receive do
         after
           :infinity -> :ok
         end
       end)}
    end
  end

  defmodule DynamicSupervisorStub do
    def terminate_child(_name, pid) when is_pid(pid) do
      Process.exit(pid, :kill)
      :ok
    end
  end
end
