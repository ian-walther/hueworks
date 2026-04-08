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

  test "publishes retained discovery and attributes payloads when connected" do
    put_export_settings(%{
      ha_export_enabled: true,
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

    assert_receive {:published, client_id, "hueworks/ha_export/status", "online",
                    [qos: 0, retain: true]}

    assert client_id == Export.client_id()

    assert_receive {:published, ^client_id, topic, payload, [qos: 0, retain: true]}
    assert topic == "homeassistant/scene/hueworks_scene_#{scene.id}/config"

    decoded = Jason.decode!(payload)
    assert decoded["name"] == "All Auto"
    assert decoded["command_topic"] == "hueworks/ha_export/scenes/#{scene.id}/set"

    assert_receive {:published, ^client_id, attrs_topic, attrs_payload, [qos: 0, retain: true]}
    assert attrs_topic == "hueworks/ha_export/scenes/#{scene.id}/attributes"

    attrs = Jason.decode!(attrs_payload)
    assert attrs["hueworks_managed"] == true
    assert attrs["hueworks_scene_id"] == scene.id
  end

  test "command topic ON activates the matching HueWorks scene" do
    put_export_settings(%{
      ha_export_enabled: true,
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

  test "command_scene_id parses scene ids from export topics" do
    assert Export.command_scene_id("hueworks/ha_export/scenes/42/set") == 42
    assert Export.command_scene_id(["hueworks", "ha_export", "scenes", "42", "set"]) == 42
    assert Export.command_scene_id("hueworks/ha_export/scenes/not-a-number/set") == nil
    assert Export.command_scene_id("hueworks/ha_export/other/42/set") == nil
  end

  defp put_export_settings(attrs) do
    {:ok, _settings} =
      AppSettings.upsert_global(
        Map.merge(
          %{
            latitude: 40.7128,
            longitude: -74.006,
            timezone: "America/New_York",
            ha_export_enabled: false,
            ha_export_discovery_prefix: "homeassistant"
          },
          attrs
        )
      )

    HueworksApp.Cache.flush_namespace(:app_settings)
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
