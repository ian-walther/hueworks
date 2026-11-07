defmodule Hueworks.ScenesCircadianFailureTest do
  use Hueworks.DataCase, async: false

  import ExUnit.CaptureLog

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Control.DesiredState
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{Area, Light, PresenceInput}

  # Midnight sun: the astronomical calculation fails while settings stay valid.
  @polar_now ~U[2026-06-21 10:00:00Z]

  setup do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 69.6492,
        longitude: 18.9553,
        timezone: "Europe/Oslo"
      })

    area = Repo.insert!(%Area{name: "Main Floor", metadata: %{}})

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.231",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :hue,
        source_id: Integer.to_string(System.unique_integer([:positive])),
        bridge_id: bridge.id,
        area_id: area.id,
        metadata: %{}
      })

    {:ok, state} = Scenes.create_light_state("Default Circadian", :circadian, %{})

    %{area: area, light: light, state: state}
  end

  test "does not emit an incomplete on command for a light without targets", context do
    scene = scene_with(context, %{})

    log =
      capture_log(fn ->
        assert {:ok, diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
        assert diff == %{}
      end)

    assert log =~ "circadian"
    assert DesiredState.get(:light, context.light.id) == nil
  end

  test "keeps a light that is off at off when the scene wants it on", context do
    scene = scene_with(context, %{})
    DesiredState.put(:light, context.light.id, %{power: :off})

    capture_log(fn ->
      assert {:ok, diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
      refute diff[{:light, context.light.id}][:power] == :on
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "preserves the existing valid targets of a light that is on", context do
    scene = scene_with(context, %{})
    targets = %{power: :on, brightness: 40, kelvin: 3000}
    DesiredState.put(:light, context.light.id, targets)

    capture_log(fn ->
      assert {:ok, diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
      assert diff == %{}
    end)

    assert DesiredState.get(:light, context.light.id) == targets
  end

  test "honors a default-off policy during a failed calculation", context do
    scene = scene_with(context, %{light_defaults: %{context.light.id => :default_off}})
    DesiredState.put(:light, context.light.id, %{power: :on, brightness: 40, kelvin: 3000})

    capture_log(fn ->
      assert {:ok, diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
      assert diff[{:light, context.light.id}][:power] == :off
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "honors force-off during a failed calculation", context do
    scene = scene_with(context, %{light_defaults: %{context.light.id => :force_off}})
    DesiredState.put(:light, context.light.id, %{power: :on, brightness: 40, kelvin: 3000})

    capture_log(fn ->
      assert {:ok, _diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "honors an unoccupied presence input during a failed calculation", context do
    input = Repo.insert!(%PresenceInput{area_id: context.area.id, name: "Hall", occupied: false})

    scene =
      scene_with(context, %{
        light_defaults: %{context.light.id => :follow_presence},
        light_presence_inputs: %{context.light.id => input.id}
      })

    DesiredState.put(:light, context.light.id, %{power: :on, brightness: 40, kelvin: 3000})

    capture_log(fn ->
      assert {:ok, _diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "an occupied presence input cannot produce an incomplete on command", context do
    input = Repo.insert!(%PresenceInput{area_id: context.area.id, name: "Hall", occupied: true})

    scene =
      scene_with(context, %{
        light_defaults: %{context.light.id => :follow_presence},
        light_presence_inputs: %{context.light.id => input.id}
      })

    DesiredState.put(:light, context.light.id, %{power: :off})

    capture_log(fn ->
      assert {:ok, diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
      assert diff == %{}
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "preserves a manual power-off latch during a failed calculation", context do
    scene = scene_with(context, %{})
    DesiredState.put(:light, context.light.id, %{power: :off})

    capture_log(fn ->
      assert {:ok, _diff, _updated} =
               Scenes.apply_scene(scene, now: @polar_now, preserve_power_latches: true)
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "honors a retained manual off override during a failed calculation", context do
    scene = scene_with(context, %{})
    DesiredState.put(:light, context.light.id, %{power: :on, brightness: 40, kelvin: 3000})

    capture_log(fn ->
      assert {:ok, _diff, _updated} =
               Scenes.apply_scene(scene,
                 now: @polar_now,
                 power_overrides: %{context.light.id => :off}
               )
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "a manual on override cannot produce an incomplete on command", context do
    scene = scene_with(context, %{})
    DesiredState.put(:light, context.light.id, %{power: :off})

    capture_log(fn ->
      assert {:ok, diff, _updated} =
               Scenes.apply_scene(scene,
                 now: @polar_now,
                 power_overrides: %{context.light.id => :on}
               )

      assert diff == %{}
    end)

    assert DesiredState.get(:light, context.light.id) == %{power: :off}
  end

  test "activating a scene during a failed calculation keeps the active scene", context do
    scene = scene_with(context, %{})

    capture_log(fn ->
      assert {:ok, diff, _updated} = Scenes.activate_scene(scene.id, now: @polar_now)
      assert diff == %{}
    end)

    assert ActiveScenes.get_for_area(context.area.id).scene_id == scene.id
    assert DesiredState.get(:light, context.light.id) == nil
  end

  test "a manual component in the same scene still applies", context do
    other =
      Repo.insert!(%Light{
        name: "Manual Lamp",
        source: :hue,
        source_id: Integer.to_string(System.unique_integer([:positive])),
        bridge_id: context.light.bridge_id,
        area_id: context.area.id,
        metadata: %{}
      })

    {:ok, manual} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Mixed", area_id: context.area.id})

    {:ok, _components} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Circadian",
          light_ids: [context.light.id],
          light_state_id: to_string(context.state.id)
        },
        %{name: "Manual", light_ids: [other.id], light_state_id: to_string(manual.id)}
      ])

    capture_log(fn ->
      assert {:ok, _diff, _updated} = Scenes.apply_scene(scene, now: @polar_now)
    end)

    assert DesiredState.get(:light, context.light.id) == nil
    assert DesiredState.get(:light, other.id) == %{power: :on, brightness: 40, kelvin: 3000}
  end

  defp scene_with(context, component_attrs) do
    {:ok, scene} = Scenes.create_scene(%{name: "Evening Auto", area_id: context.area.id})

    {:ok, _components} =
      Scenes.replace_scene_components(scene, [
        Map.merge(
          %{
            name: "Everything",
            light_ids: [context.light.id],
            light_state_id: to_string(context.state.id)
          },
          component_attrs
        )
      ])

    scene
  end
end
