defmodule Hueworks.GlobalSolarTimingIntegrationTest do
  use Hueworks.DataCase, async: false

  import ExUnit.CaptureLog

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Circadian
  alias Hueworks.Control.{CircadianPoller, DesiredState}
  alias Hueworks.Lights.ManualControl
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Area, Light, LightState, PresenceInput}

  # An hour after the astronomical winter sunset, an hour before the 18:00 bound.
  @now DateTime.new!(~D[2026-12-21], ~T[17:15:00], "America/Los_Angeles")

  @profile_ranges %{
    "min_brightness" => 10,
    "max_brightness" => 90,
    "min_color_temp" => 2000,
    "max_color_temp" => 4000
  }

  setup do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 47.6062,
        longitude: -122.3321,
        timezone: "America/Los_Angeles"
      })

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.232",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })

    {:ok, default_circadian} =
      Scenes.create_light_state("Default Circadian", :circadian, @profile_ranges)

    {:ok, foyer_circadian} =
      Scenes.create_light_state(
        "Foyer Circadian",
        :circadian,
        Map.merge(@profile_ranges, %{
          "override_sunrise_timing" => true,
          "override_sunset_timing" => true,
          "sunset_time" => "16:00:00",
          "sunrise_time" => "07:00:00"
        })
      )

    {:ok, manual} =
      Scenes.create_manual_light_state("Bright", %{"brightness" => "80", "temperature" => "3000"})

    %{
      bridge: bridge,
      default_circadian: default_circadian,
      foyer_circadian: foyer_circadian,
      manual: manual
    }
  end

  defp insert_area_light(context, area_name) do
    area = Repo.insert!(%Area{name: area_name, metadata: %{}})

    light =
      Repo.insert!(%Light{
        name: "#{area_name} Lamp",
        source: :hue,
        source_id: Integer.to_string(System.unique_integer([:positive])),
        bridge_id: context.bridge.id,
        area_id: area.id,
        supports_temp: true,
        metadata: %{}
      })

    {area, light}
  end

  defp active_scene(area, light, light_state, component_attrs \\ %{}) do
    {:ok, scene} = Scenes.create_scene(%{name: "#{area.name} Auto", area_id: area.id})

    {:ok, _components} =
      Scenes.replace_scene_components(scene, [
        Map.merge(
          %{
            name: "Everything",
            light_ids: [light.id],
            light_state_id: to_string(light_state.id)
          },
          component_attrs
        )
      ])

    {:ok, _active} = ActiveScenes.set_active(scene, now: @now)
    {:ok, _diff, _updated} = Scenes.apply_scene(scene, now: @now)

    scene
  end

  defp direct_targets(%LightState{} = state) do
    {:ok, result} =
      state
      |> LightState.circadian_config()
      |> Circadian.calculate(AppSettings.solar_config(), @now)

    %{power: :on, brightness: result.brightness, kelvin: result.kelvin}
  end

  test "an accepted bound reaches shared inheriting scenes on the next poll", context do
    {main_area, main_light} = insert_area_light(context, "Main Floor")
    {garage_area, garage_light} = insert_area_light(context, "Garage")

    main_scene = active_scene(main_area, main_light, context.default_circadian)
    garage_scene = active_scene(garage_area, garage_light, context.default_circadian)

    baseline = DesiredState.get(:light, main_light.id)
    revision = DesiredState.revision(:light, main_light.id)

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})

    # The settings write dispatches nothing; adaptation picks it up on its own cycle.
    assert DesiredState.get(:light, main_light.id) == baseline
    assert DesiredState.revision(:light, main_light.id) == revision

    assert :ok = CircadianPoller.run_tick(@now)

    expected = direct_targets(context.default_circadian)

    refute expected == baseline
    assert DesiredState.get(:light, main_light.id) == expected
    assert DesiredState.get(:light, garage_light.id) == expected

    assert ActiveScenes.get_for_area(main_area.id).scene_id == main_scene.id
    assert ActiveScenes.get_for_area(garage_area.id).scene_id == garage_scene.id
  end

  test "clearing the bound returns inheriting scenes to astronomical timing", context do
    {area, light} = insert_area_light(context, "Main Floor")
    active_scene(area, light, context.default_circadian)
    astronomical = DesiredState.get(:light, light.id)

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
    CircadianPoller.run_tick(@now)
    refute DesiredState.get(:light, light.id) == astronomical

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: ""})
    CircadianPoller.run_tick(@now)
    assert DesiredState.get(:light, light.id) == astronomical
  end

  test "overridden and manual profiles keep their configured behavior", context do
    {foyer_area, foyer_light} = insert_area_light(context, "Foyer")
    {studio_area, studio_light} = insert_area_light(context, "Studio")

    active_scene(foyer_area, foyer_light, context.foyer_circadian)
    active_scene(studio_area, studio_light, context.manual)

    foyer_baseline = DesiredState.get(:light, foyer_light.id)
    studio_baseline = DesiredState.get(:light, studio_light.id)

    {:ok, _settings} =
      AppSettings.upsert_global(%{min_sunset_time: "18:00", max_sunrise_time: "06:00"})

    CircadianPoller.run_tick(@now)

    assert DesiredState.get(:light, foyer_light.id) == foyer_baseline
    assert DesiredState.get(:light, studio_light.id) == studio_baseline
  end

  test "a manual off latch survives a global change and adaptation", context do
    {area, light} = insert_area_light(context, "Main Floor")
    active_scene(area, light, context.default_circadian)

    assert {:ok, _diff} = ManualControl.apply_power_action(area.id, [light.id], :off)
    assert DesiredState.get(:light, light.id) == %{power: :off}

    overrides = ActiveScenes.power_overrides(ActiveScenes.get_for_area(area.id))

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
    CircadianPoller.run_tick(@now)

    assert DesiredState.get(:light, light.id) == %{power: :off}
    assert ActiveScenes.power_overrides(ActiveScenes.get_for_area(area.id)) == overrides
  end

  test "a presence gate stays closed while targets adapt for occupied lights", context do
    {area, off_light} = insert_area_light(context, "Hallway")

    on_light =
      Repo.insert!(%Light{
        name: "Hallway Occupied",
        source: :hue,
        source_id: Integer.to_string(System.unique_integer([:positive])),
        bridge_id: context.bridge.id,
        area_id: area.id,
        supports_temp: true,
        metadata: %{}
      })

    vacant = Repo.insert!(%PresenceInput{area_id: area.id, name: "Vacant", occupied: false})
    occupied = Repo.insert!(%PresenceInput{area_id: area.id, name: "Occupied", occupied: true})

    {:ok, scene} = Scenes.create_scene(%{name: "Hallway Auto", area_id: area.id})

    {:ok, _components} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Follows presence",
          light_ids: [off_light.id, on_light.id],
          light_state_id: to_string(context.default_circadian.id),
          light_defaults: %{off_light.id => :follow_presence, on_light.id => :follow_presence},
          light_presence_inputs: %{off_light.id => vacant.id, on_light.id => occupied.id}
        }
      ])

    {:ok, _active} = ActiveScenes.set_active(scene, now: @now)
    {:ok, _diff, _updated} = Scenes.apply_scene(scene, now: @now)

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
    CircadianPoller.run_tick(@now)

    assert DesiredState.get(:light, off_light.id) == %{power: :off}
    assert DesiredState.get(:light, on_light.id) == direct_targets(context.default_circadian)
  end

  test "an off scene referencing an inheriting profile stays off", context do
    {area, light} = insert_area_light(context, "Guest Room")

    active_scene(area, light, context.default_circadian, %{
      light_defaults: %{light.id => :force_off}
    })

    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})
    CircadianPoller.run_tick(@now)

    assert DesiredState.get(:light, light.id) == %{power: :off}
  end

  test "a seasonal calculation failure holds targets through a poll", context do
    {area, light} = insert_area_light(context, "Main Floor")
    active_scene(area, light, context.default_circadian)
    targets = DesiredState.get(:light, light.id)

    {:ok, _settings} =
      AppSettings.upsert_global(%{latitude: 69.6492, longitude: 18.9553, timezone: "Europe/Oslo"})

    log =
      capture_log(fn ->
        assert :ok = CircadianPoller.run_tick(~U[2026-06-21 10:00:00Z])
      end)

    assert log =~ "sun_event_unavailable"
    assert DesiredState.get(:light, light.id) == targets
  end
end
