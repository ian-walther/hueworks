defmodule Hueworks.HomeAssistant.ExportSettingsTest do
  use Hueworks.DataCase, async: false

  import ExUnit.CaptureLog

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Control.DesiredState
  alias Hueworks.HomeAssistant.Export
  alias Hueworks.HomeAssistant.Export.Connection
  alias Hueworks.HomeAssistant.Export.Messages
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{AppSetting, Area, Group, GroupLight, Light}
  alias Phoenix.PubSub

  @fields [:min_sunrise_time, :max_sunrise_time, :min_sunset_time, :max_sunset_time]
  @availability "hueworks/ha_export/status"

  setup do
    env_keys = [
      :ha_export_tortoise_module,
      :ha_export_tortoise_supervisor_module,
      :ha_export_dynamic_supervisor_module,
      :ha_export_tortoise_supervisor_name,
      :ha_export_publish_sink,
      :ha_export_stub_start_results
    ]

    original_env = Map.new(env_keys, &{&1, Application.get_env(:hueworks, &1)})

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
    Application.delete_env(:hueworks, :ha_export_stub_start_results)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} -> restore_app_env(:hueworks, key, value) end)
    end)

    Repo.delete_all(AppSetting)

    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 47.6062,
        longitude: -122.3321,
        timezone: "America/Los_Angeles",
        ha_export_scenes_enabled: true,
        ha_export_mqtt_host: "mqtt.local"
      })

    start_supervised!({Export, []})
    assert_receive {:start_child, _opts}
    connect()

    :ok
  end

  defp connect do
    send(Export, {:mqtt_connected, Export.client_id()})
    _state = :sys.get_state(Export)
    session()
  end

  defp session, do: :sys.get_state(Export).settings_session

  defp command_topic_levels(field), do: String.split(Messages.setting_command_topic(field), "/")

  defp send_command(field, payload) do
    send(Export, {:mqtt_message, command_topic_levels(field), payload})
    _state = :sys.get_state(Export)
    :ok
  end

  defp send_value(field, value, session \\ session()) do
    send_command(field, Jason.encode!(%{"value" => value, "session" => session}))
  end

  defp persisted(field), do: Repo.get_by!(AppSetting, scope: "global") |> Map.fetch!(field)

  defp drain_published do
    receive do
      {:published, _topic, _payload, _opts} -> drain_published()
    after
      0 -> :ok
    end
  end

  defp assert_latest_state(field, value) do
    topic = Messages.setting_state_topic(field)
    payload = Jason.encode!(%{"value" => value})
    assert_receive {:published, ^topic, ^payload, [qos: 0, retain: true]}
  end

  defp discovery(field) do
    topic = "homeassistant/text/hueworks_setting_#{field}/config"
    assert_receive {:published, ^topic, payload, [qos: 0, retain: true]}
    Jason.decode!(payload)
  end

  describe "discovery" do
    test "publishes a stable text entity for each bound" do
      expected = %{
        min_sunrise_time: {"Sunrise minimum", "text.hueworks_sunrise_minimum"},
        max_sunrise_time: {"Sunrise maximum", "text.hueworks_sunrise_maximum"},
        min_sunset_time: {"Sunset minimum", "text.hueworks_sunset_minimum"},
        max_sunset_time: {"Sunset maximum", "text.hueworks_sunset_maximum"}
      }

      for {field, {name, entity_id}} <- expected do
        payload = discovery(field)

        assert payload["platform"] == "text"
        assert payload["name"] == name
        assert payload["default_entity_id"] == entity_id
        assert payload["unique_id"] == "hueworks_setting_#{field}"
        assert payload["command_topic"] == "hueworks/ha_export/settings/#{field}/set"
        assert payload["state_topic"] == "hueworks/ha_export/settings/#{field}/state"
        assert payload["value_template"] == "{{ value_json.value }}"
        assert payload["retain"] == false
        assert payload["availability_topic"] == @availability
        assert payload["payload_available"] == "online"
        assert payload["payload_not_available"] == "offline"
        assert payload["device"]["identifiers"] == ["hueworks_global_settings"]
        assert payload["device"]["name"] == "HueWorks"
      end
    end

    test "the command template wraps the value and the current session" do
      payload = discovery(:min_sunset_time)

      assert payload["command_template"] ==
               ~s({"value": {{ value | to_json }}, "session": "#{session()}"})
    end

    test "the pattern accepts blank and wall-clock times but not fake values" do
      {:ok, pattern} = Regex.compile(discovery(:min_sunset_time)["pattern"])

      for value <- ["", "00:00", "18:00", "18:00:30", "23:59:59"] do
        assert Regex.match?(pattern, value), "expected #{inspect(value)} to match"
      end

      for value <- ["24:00", "6:00", "unknown", "unavailable", "18:60", "18:00:60"] do
        refute Regex.match?(pattern, value), "expected #{inspect(value)} not to match"
      end
    end

    test "an unset bound publishes a nonempty retained envelope" do
      for field <- @fields do
        topic = Messages.setting_state_topic(field)
        assert_receive {:published, ^topic, ~s({"value":""}), [qos: 0, retain: true]}
      end
    end

    test "publishes the bound's persisted value" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      drain_published()

      connect()

      assert_latest_state(:min_sunset_time, "18:00:00")
      assert_latest_state(:max_sunset_time, "")
    end
  end

  describe "commands" do
    setup do
      drain_published()
      :ok
    end

    test "a valid command persists and publishes the accepted state" do
      send_value(:min_sunset_time, "18:00")

      assert persisted(:min_sunset_time) == "18:00:00"
      assert_latest_state(:min_sunset_time, "18:00:00")
    end

    for value <- ["18:00:00.5", "18:00:00+05:00", "18:00:00Z", "T18:00:00", "18:00:60", "7:30"] do
      test "rejects #{value} and reports the accepted state" do
        {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
        drain_published()

        log = capture_log(fn -> send_value(:min_sunset_time, unquote(value)) end)

        assert log =~ "HA export setting command ignored"
        assert persisted(:min_sunset_time) == "18:00:00"
        assert_latest_state(:min_sunset_time, "18:00:00")
      end
    end

    test "a blank value and null both clear the bound" do
      for clear <- ["", nil] do
        {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
        drain_published()

        send_value(:min_sunset_time, clear)

        assert persisted(:min_sunset_time) == nil
        assert_latest_state(:min_sunset_time, "")
      end
    end

    test "midnight stays a real value" do
      send_value(:min_sunrise_time, "00:00")

      assert persisted(:min_sunrise_time) == "00:00:00"
      assert_latest_state(:min_sunrise_time, "00:00:00")
    end

    test "an invalid command keeps the last accepted value and reports it again" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      drain_published()

      for value <- ["25:00", "later", "unknown", 1800, true, %{"a" => 1}] do
        log = capture_log(fn -> send_value(:min_sunset_time, value) end)

        assert log =~ "HA export setting command ignored"
        assert persisted(:min_sunset_time) == "18:00:00"
        assert_latest_state(:min_sunset_time, "18:00:00")
      end
    end

    test "a payload outside the envelope is ignored" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      drain_published()

      for payload <- ["", "19:00", "[]", ~s({"value":"19:00"}), ~s({"session":"x"})] do
        log = capture_log(fn -> send_command(:min_sunset_time, payload) end)

        assert log =~ "HA export setting command ignored"
        assert persisted(:min_sunset_time) == "18:00:00"
      end
    end

    test "an inverted pair is rejected through the settings boundary" do
      send_value(:max_sunset_time, "20:00")
      drain_published()

      log = capture_log(fn -> send_value(:min_sunset_time, "21:00") end)

      assert log =~ "min_sunset_time must be less than or equal to max_sunset_time"
      assert persisted(:min_sunset_time) == nil
      assert_latest_state(:min_sunset_time, "")
    end

    test "an ordering conflict is rejected and names the profile" do
      {:ok, _state} =
        Scenes.create_light_state("Warm Circadian", :circadian, %{
          "override_sunset_timing" => true,
          "sunset_time" => "18:00:00",
          "brightness_sunset_offset" => -18_000
        })

      log = capture_log(fn -> send_value(:min_sunrise_time, "10:00") end)

      assert log =~ "Warm Circadian"
      assert persisted(:min_sunrise_time) == nil
    end

    test "a repeated command is harmless and dispatches nothing" do
      area = Repo.insert!(%Area{name: "Main Floor", metadata: %{}})

      bridge =
        insert_bridge!(%{
          type: :hue,
          name: "Hue Bridge",
          host: "10.0.0.233",
          credentials: %{"api_key" => "key"},
          import_complete: false,
          enabled: true
        })

      light =
        Repo.insert!(%Light{
          name: "Lamp",
          source: :hue,
          source_id: "1",
          bridge_id: bridge.id,
          area_id: area.id,
          metadata: %{}
        })

      {:ok, state} = Scenes.create_light_state("Default Circadian", :circadian, %{})
      {:ok, scene} = Scenes.create_scene(%{name: "Evening Auto", area_id: area.id})

      {:ok, _components} =
        Scenes.replace_scene_components(scene, [
          %{name: "All", light_ids: [light.id], light_state_id: to_string(state.id)}
        ])

      {:ok, _active} = ActiveScenes.set_active(scene)
      {:ok, _diff, _updated} = Scenes.apply_scene(scene)

      revision = DesiredState.revision(:light, light.id)
      active_before = ActiveScenes.get_for_area(area.id)

      send_value(:min_sunset_time, "18:00")
      first_write = Repo.get_by!(AppSetting, scope: "global")
      drain_published()

      PubSub.subscribe(Hueworks.PubSub, "domain_events")
      send_value(:min_sunset_time, "18:00")

      refute_receive {:global_settings_changed, _fields}, 50
      assert_latest_state(:min_sunset_time, "18:00:00")
      assert Repo.get_by!(AppSetting, scope: "global") == first_write
      assert DesiredState.revision(:light, light.id) == revision
      assert ActiveScenes.get_for_area(area.id) == active_before
    end

    test "commands are ignored once export is disabled" do
      {:ok, _settings} = AppSettings.upsert_global(%{ha_export_scenes_enabled: false})
      Export.reload()
      old_session = session()

      send_value(:min_sunset_time, "18:00", old_session)

      assert persisted(:min_sunset_time) == nil
    end
  end

  describe "stale and replayed commands" do
    test "a command from an earlier connection cannot overwrite newer settings" do
      old_session = session()
      stale = Jason.encode!(%{"value" => "21:00", "session" => old_session})

      new_session = connect()
      refute new_session == old_session

      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      drain_published()

      log = capture_log(fn -> send_command(:min_sunset_time, stale) end)

      assert log =~ "stale_session"
      assert persisted(:min_sunset_time) == "18:00:00"
      assert_latest_state(:min_sunset_time, "18:00:00")
    end

    test "a retained command delivered right after reconnecting is not applied" do
      stale = Jason.encode!(%{"value" => "21:00", "session" => session()})

      # The handler sends both from one process, in this order.
      send(Export, {:mqtt_connected, Export.client_id()})
      send(Export, {:mqtt_message, command_topic_levels(:min_sunset_time), stale})

      capture_log(fn -> _state = :sys.get_state(Export) end)

      assert persisted(:min_sunset_time) == nil
    end

    test "reconnecting republishes discovery with the new session" do
      old_payload = discovery(:min_sunset_time)
      drain_published()

      new_session = connect()
      new_payload = discovery(:min_sunset_time)

      refute new_payload["command_template"] == old_payload["command_template"]
      assert new_payload["command_template"] =~ new_session
      assert new_payload["unique_id"] == old_payload["unique_id"]
      assert new_payload["default_entity_id"] == old_payload["default_entity_id"]
    end

    test "a command without a live session is rejected" do
      {:ok, _settings} = AppSettings.upsert_global(%{ha_export_mqtt_host: "other.local"})
      Export.reload()
      _state = :sys.get_state(Export)
      assert session() == nil

      capture_log(fn ->
        send_command(:min_sunset_time, ~s({"value":"18:00","session":null}))
        send_value(:min_sunset_time, "18:00", "guess")
      end)

      assert persisted(:min_sunset_time) == nil
    end

    test "deleting a retained command is not a clear and does not crash the exporter" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      exporter = Process.whereis(Export)

      send(Export, {:mqtt_message, command_topic_levels(:min_sunset_time), nil})
      _state = :sys.get_state(Export)

      assert Process.whereis(Export) == exporter
      assert persisted(:min_sunset_time) == "18:00:00"
    end

    test "deleting a retained area select command does not clear the active scene" do
      area = Repo.insert!(%Area{name: "Main Floor", metadata: %{}})
      {:ok, scene} = Scenes.create_scene(%{name: "Evening Auto", area_id: area.id})
      {:ok, _active} = ActiveScenes.set_active(scene)

      send(
        Export,
        {:mqtt_message, String.split(Messages.area_select_command_topic(area.id), "/"), nil}
      )

      _state = :sys.get_state(Export)

      assert ActiveScenes.get_for_area(area.id).scene_id == scene.id
    end
  end

  describe "both-direction updates" do
    setup do
      drain_published()
      :ok
    end

    test "a change from HueWorks reaches Home Assistant without a new session" do
      current = session()

      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})

      assert_latest_state(:min_sunset_time, "18:00:00")
      assert session() == current
    end

    test "clearing from HueWorks publishes the blank envelope" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
      assert_latest_state(:min_sunset_time, "18:00:00")

      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: ""})

      assert_latest_state(:min_sunset_time, "")
    end

    test "an unrelated settings change publishes no bound state" do
      {:ok, _settings} = AppSettings.upsert_global(%{default_transition_ms: 900})
      _state = :sys.get_state(Export)

      for field <- @fields do
        topic = Messages.setting_state_topic(field)
        refute_received {:published, ^topic, _payload, _opts}
      end
    end
  end

  describe "availability and lifecycle" do
    test "accepted values always fit the entity's published length" do
      for value <- ["00:00", "18:00", "23:59:59"] do
        send_value(:min_sunset_time, value)
        assert String.length(persisted(:min_sunset_time)) == 8
      end
    end

    test "the broker holds an offline last will on the availability topic" do
      {:ok, _settings} = AppSettings.upsert_global(%{ha_export_mqtt_host: "broker.local"})
      Export.reload()

      assert_receive {:start_child, opts}

      assert %Tortoise.Package.Publish{
               topic: @availability,
               payload: "offline",
               qos: 0,
               retain: true
             } = opts[:will]
    end

    test "the last will encodes into the MQTT CONNECT packet as retained" do
      {:ok, _settings} = AppSettings.upsert_global(%{ha_export_mqtt_host: "broker.local"})
      Export.reload()
      assert_receive {:start_child, opts}

      decoded =
        %Tortoise.Package.Connect{client_id: "hueworks-test", will: opts[:will]}
        |> Tortoise.Package.encode()
        |> IO.iodata_to_binary()
        |> Tortoise.Package.decode()

      assert %{topic: @availability, payload: "offline", retain: true} = decoded.will
    end

    test "connecting reports online after the will could have reported offline" do
      assert_receive {:published, @availability, "online", [qos: 0, retain: true]}
    end

    test "disabling export removes the entities and reports offline" do
      drain_published()

      {:ok, _settings} = AppSettings.upsert_global(%{ha_export_scenes_enabled: false})
      Export.reload()
      _state = :sys.get_state(Export)

      for field <- @fields do
        discovery_topic = "homeassistant/text/hueworks_setting_#{field}/config"
        state_topic = Messages.setting_state_topic(field)

        assert_receive {:published, ^discovery_topic, "", [qos: 0, retain: true]}
        assert_receive {:published, ^state_topic, "", [qos: 0, retain: true]}
      end

      assert_receive {:published, @availability, "offline", [qos: 0, retain: true]}
      assert session() == nil
    end

    test "a surviving connection is replaced so its handler reports to this exporter" do
      survivor =
        spawn(fn ->
          receive do
          after
            :infinity -> :ok
          end
        end)

      Application.put_env(:hueworks, :ha_export_stub_start_results, [
        {:error, {:already_started, survivor}}
      ])

      config = Export.export_config()

      assert {:ok, replacement} =
               Connection.start("hueworks-test", self(), config, ["a/topic"])

      assert_receive {:terminated, ^survivor}
      refute replacement == survivor

      assert_receive {:start_child, first_opts}
      assert_receive {:start_child, second_opts}
      assert first_opts == second_opts

      assert {Hueworks.HomeAssistant.Export.Handler, [handler_server | _rest]} =
               second_opts[:handler]

      assert handler_server == self()
    end
  end

  describe "optimistic power state" do
    setup do
      area = Repo.insert!(%Area{name: "Main Floor", metadata: %{}})

      bridge =
        insert_bridge!(%{
          type: :hue,
          name: "Hue Bridge",
          host: "10.0.0.234",
          credentials: %{"api_key" => "key"},
          import_complete: false,
          enabled: true
        })

      # A zero-width ramp fails the calculation on any date.
      {:ok, unavailable} =
        Scenes.create_light_state("Unavailable", :circadian, %{
          "override_sunrise_timing" => true,
          "override_sunset_timing" => true,
          "sunrise_time" => "06:00:00",
          "sunset_time" => "18:00:00",
          "brightness_mode" => "linear",
          "brightness_mode_time_dark" => 0,
          "brightness_mode_time_light" => 0
        })

      %{area: area, bridge: bridge, unavailable: unavailable}
    end

    defp insert_exported_light(context, mode) do
      Repo.insert!(%Light{
        name: "Lamp",
        source: :hue,
        source_id: Integer.to_string(System.unique_integer([:positive])),
        bridge_id: context.bridge.id,
        area_id: context.area.id,
        supports_temp: true,
        ha_export_mode: mode,
        metadata: %{}
      })
    end

    defp activate_unavailable_scene(context, light) do
      {:ok, scene} = Scenes.create_scene(%{name: "Evening Auto", area_id: context.area.id})

      {:ok, _components} =
        Scenes.replace_scene_components(scene, [
          %{
            name: "All",
            light_ids: [light.id],
            light_state_id: to_string(context.unavailable.id)
          }
        ])

      {:ok, _active} = ActiveScenes.set_active(scene)
      DesiredState.put(:light, light.id, %{power: :off})
      drain_published()
    end

    defp send_light_command(light, mode, payload) do
      levels = ["hueworks", "ha_export", "lights", Integer.to_string(light.id), mode, "set"]
      send(Export, {:mqtt_message, levels, payload})
      _state = :sys.get_state(Export)
    end

    test "a held switch command does not claim the light turned on", context do
      light = insert_exported_light(context, :switch)
      activate_unavailable_scene(context, light)
      topic = Messages.switch_state_topic(:light, light.id)

      log = capture_log(fn -> send_light_command(light, "switch", "ON") end)

      assert log =~ "Holding circadian targets"
      assert DesiredState.get(:light, light.id) == %{power: :off}
      refute_received {:published, ^topic, "ON", _opts}
    end

    test "a held light command does not claim the light turned on", context do
      light = insert_exported_light(context, :light)
      activate_unavailable_scene(context, light)
      topic = Messages.light_state_topic(:light, light.id)

      capture_log(fn -> send_light_command(light, "light", ~s({"state":"ON"})) end)

      assert DesiredState.get(:light, light.id) == %{power: :off}
      refute_received {:published, ^topic, _payload, _opts}
    end

    test "an accepted on command still publishes its optimistic state", context do
      light = insert_exported_light(context, :switch)
      topic = Messages.switch_state_topic(:light, light.id)
      drain_published()

      send_light_command(light, "switch", "ON")

      assert DesiredState.get(:light, light.id)[:power] == :on
      assert_received {:published, ^topic, "ON", [qos: 0, retain: true]}
    end

    test "an off command still publishes during a failed calculation", context do
      light = insert_exported_light(context, :switch)
      activate_unavailable_scene(context, light)
      DesiredState.put(:light, light.id, %{power: :on, brightness: 40, kelvin: 3000})
      topic = Messages.switch_state_topic(:light, light.id)

      capture_log(fn -> send_light_command(light, "switch", "OFF") end)

      assert DesiredState.get(:light, light.id) == %{power: :off}
      assert_received {:published, ^topic, "OFF", [qos: 0, retain: true]}
    end

    defp insert_exported_group(context, lights) do
      group =
        Repo.insert!(%Group{
          name: "Pendants",
          source: :hue,
          source_id: Integer.to_string(System.unique_integer([:positive])),
          bridge_id: context.bridge.id,
          area_id: context.area.id,
          ha_export_mode: :switch,
          metadata: %{}
        })

      Enum.each(lights, &Repo.insert!(%GroupLight{group_id: group.id, light_id: &1.id}))

      group
    end

    defp activate_manual_scene(context, lights, light_defaults) do
      {:ok, manual} =
        Scenes.create_manual_light_state("Bright", %{
          "brightness" => "80",
          "temperature" => "3000"
        })

      {:ok, scene} = Scenes.create_scene(%{name: "Bright", area_id: context.area.id})

      {:ok, _components} =
        Scenes.replace_scene_components(scene, [
          %{
            name: "All",
            light_ids: Enum.map(lights, & &1.id),
            light_state_id: to_string(manual.id),
            light_defaults: light_defaults
          }
        ])

      {:ok, _active} = ActiveScenes.set_active(scene)
      {:ok, _diff, _updated} = Scenes.apply_scene(scene)
      drain_published()
    end

    defp send_group_command(group, payload) do
      levels = ["hueworks", "ha_export", "groups", Integer.to_string(group.id), "switch", "set"]
      send(Export, {:mqtt_message, levels, payload})
      _state = :sys.get_state(Export)
    end

    test "off is not claimed for a group while a member stays on", context do
      free = insert_exported_light(context, :none)
      forced = insert_exported_light(context, :none)
      group = insert_exported_group(context, [free, forced])
      activate_manual_scene(context, [free, forced], %{forced.id => :force_on})
      topic = Messages.switch_state_topic(:group, group.id)

      send_group_command(group, "OFF")

      assert DesiredState.get(:light, free.id)[:power] == :off
      assert DesiredState.get(:light, forced.id)[:power] == :on
      refute_received {:published, ^topic, "OFF", _opts}
    end

    test "off is claimed for a group once every member is off", context do
      first = insert_exported_light(context, :none)
      second = insert_exported_light(context, :none)
      group = insert_exported_group(context, [first, second])
      activate_manual_scene(context, [first, second], %{})
      topic = Messages.switch_state_topic(:group, group.id)

      send_group_command(group, "OFF")

      assert_received {:published, ^topic, "OFF", [qos: 0, retain: true]}
    end

    test "on is claimed for a group when any member turns on", context do
      free = insert_exported_light(context, :none)
      forced = insert_exported_light(context, :none)
      group = insert_exported_group(context, [free, forced])
      activate_manual_scene(context, [free, forced], %{forced.id => :force_off})
      assert {:ok, _diff} = ManualControl.apply_power_action(context.area.id, [free.id], :off)
      drain_published()
      topic = Messages.switch_state_topic(:group, group.id)

      send_group_command(group, "ON")

      assert DesiredState.get(:light, free.id)[:power] == :on
      assert DesiredState.get(:light, forced.id)[:power] == :off
      assert_received {:published, ^topic, "ON", [qos: 0, retain: true]}
    end

    test "on is not claimed for a group when every member is held", context do
      first = insert_exported_light(context, :none)
      second = insert_exported_light(context, :none)
      group = insert_exported_group(context, [first, second])
      {:ok, scene} = Scenes.create_scene(%{name: "Evening Auto", area_id: context.area.id})

      {:ok, _components} =
        Scenes.replace_scene_components(scene, [
          %{
            name: "All",
            light_ids: [first.id, second.id],
            light_state_id: to_string(context.unavailable.id)
          }
        ])

      {:ok, _active} = ActiveScenes.set_active(scene)
      DesiredState.put(:light, first.id, %{power: :off})
      DesiredState.put(:light, second.id, %{power: :off})
      drain_published()
      topic = Messages.switch_state_topic(:group, group.id)

      capture_log(fn -> send_group_command(group, "ON") end)

      refute_received {:published, ^topic, "ON", _opts}
    end
  end

  defmodule TortoiseStub do
    def publish(_client_id, topic, payload, opts) do
      send(
        Application.fetch_env!(:hueworks, :ha_export_publish_sink),
        {:published, topic, payload, opts}
      )

      :ok
    end
  end

  defmodule SupervisorStub do
    def start_child(opts) do
      send(Application.fetch_env!(:hueworks, :ha_export_publish_sink), {:start_child, opts})

      case Application.get_env(:hueworks, :ha_export_stub_start_results, []) do
        [result | rest] ->
          Application.put_env(:hueworks, :ha_export_stub_start_results, rest)
          result

        [] ->
          {:ok,
           spawn(fn ->
             receive do
             after
               :infinity -> :ok
             end
           end)}
      end
    end
  end

  defmodule DynamicSupervisorStub do
    def terminate_child(_name, pid) when is_pid(pid) do
      send(Application.fetch_env!(:hueworks, :ha_export_publish_sink), {:terminated, pid})
      Process.exit(pid, :kill)
      :ok
    end
  end
end
