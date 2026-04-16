defmodule Hueworks.ScenesComponentsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.AppSettings
  alias Hueworks.ActiveScenes
  alias Hueworks.Color
  alias Hueworks.Control.{DesiredState, Executor}
  alias Hueworks.Lights.ManualControl

  alias Hueworks.Schemas.{
    ActiveScene,
    Light,
    LightState,
    Room,
    SceneComponent,
    SceneComponentLight
  }

  defp insert_room do
    Repo.insert!(%Room{name: "Studio", metadata: %{}})
  end

  defp insert_bridge do
    insert_bridge!(%{
      type: :hue,
      name: "Hue Bridge",
      host: "10.0.0.230",
      credentials: %{"api_key" => "key"},
      import_complete: false,
      enabled: true
    })
  end

  defp insert_light(room, bridge, attrs) do
    defaults = %{
      name: "Light",
      source: :hue,
      source_id: Integer.to_string(System.unique_integer([:positive])),
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{}
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  test "replace_scene_components persists components and lights" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    {:ok, state} = Scenes.create_manual_light_state("Soft")

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    components = [
      %{name: "Component 1", light_ids: [light1.id], light_state_id: to_string(state.id)},
      %{name: "Component 2", light_ids: [light2.id], light_state_id: to_string(state.id)}
    ]

    {:ok, _} = Scenes.replace_scene_components(scene, components)

    scene_components =
      Repo.all(from(sc in SceneComponent, where: sc.scene_id == ^scene.id, preload: [:lights]))

    assert Enum.count(scene_components) == 2
    assert Enum.any?(scene_components, fn sc -> Enum.map(sc.lights, & &1.id) == [light1.id] end)
    assert Enum.any?(scene_components, fn sc -> Enum.map(sc.lights, & &1.id) == [light2.id] end)
  end

  test "replace_scene_components returns an error when no light state is specified" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    assert {:error, :invalid_light_state} =
             Scenes.replace_scene_components(scene, [
               %{name: "Component 1", light_ids: [light.id]}
             ])
  end

  test "replace_scene_components rejects manual color states for non-color lights" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp", supports_color: false})

    {:ok, state} =
      Scenes.create_manual_light_state("Color", %{
        "mode" => "color",
        "brightness" => "70",
        "hue" => "210",
        "saturation" => "60"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    assert {:error, :invalid_color_targets} =
             Scenes.replace_scene_components(scene, [
               %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
             ])
  end

  test "replace_scene_components rejects atom-keyed manual color states for non-color lights" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp", supports_color: false})

    state =
      Repo.insert!(%LightState{
        name: "Color",
        type: :manual,
        config: %{mode: :color, brightness: 70, hue: 210, saturation: 60}
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    assert {:error, :invalid_color_targets} =
             Scenes.replace_scene_components(scene, [
               %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
             ])
  end

  test "replace_scene_components uses selected manual light states without creating new ones" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    scene_component =
      Repo.one(
        from(sc in SceneComponent,
          where: sc.scene_id == ^scene.id,
          preload: [:light_state]
        )
      )

    assert scene_component.light_state_id == state.id
    assert Repo.aggregate(from(ls in LightState, where: ls.type == :manual), :count) == 1
  end

  test "replace_scene_components does not delete unused manual light states" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, other_state} = Scenes.create_manual_light_state("Warm")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(other_state.id)}
      ])

    assert Repo.get(LightState, state.id)
  end

  test "list_manual_light_states returns manual states" do
    {:ok, _state} = Scenes.create_manual_light_state("Bright")

    names = Scenes.list_manual_light_states() |> Enum.map(& &1.name)

    assert "Bright" in names
  end

  test "replace_scene_components removes old join rows" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})
    {:ok, state} = Scenes.create_manual_light_state("Soft")

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(state.id)
        }
      ])

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light1.id], light_state_id: to_string(state.id)}
      ])

    join_count =
      Repo.aggregate(
        from(scl in SceneComponentLight,
          join: sc in SceneComponent,
          on: sc.id == scl.scene_component_id,
          where: sc.scene_id == ^scene.id
        ),
        :count
      )

    assert join_count == 1
  end

  test "replace_scene_components persists per-light default power values" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, state} = Scenes.create_manual_light_state("Soft")
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(state.id),
          light_defaults: %{light1.id => :force_on, light2.id => :force_off}
        }
      ])

    persisted_defaults =
      Repo.all(
        from(scl in SceneComponentLight,
          join: sc in SceneComponent,
          on: sc.id == scl.scene_component_id,
          where: sc.scene_id == ^scene.id,
          select: {scl.light_id, scl.default_power}
        )
      )
      |> Map.new()

    assert persisted_defaults[light1.id] == :force_on
    assert persisted_defaults[light2.id] == :force_off
  end

  test "refresh_active_scene reapplies updated scene component state immediately" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state_a} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, state_b} =
      Scenes.create_manual_light_state("Warm", %{"brightness" => "60", "temperature" => "3500"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state_a.id)}
      ])

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, _diff, _updated} = Scenes.apply_scene(scene)

    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 40, kelvin: 3000}

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state_b.id)}
      ])

    assert {:ok, _diff, _updated} = Scenes.refresh_active_scene(scene.id)
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 60, kelvin: 3500}
    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
  end

  test "refresh_active_scenes_for_light_state reapplies active scenes using the updated light state" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, _diff, _updated} = Scenes.apply_scene(scene)

    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 40, kelvin: 3000}

    {:ok, _updated_state} =
      Scenes.update_light_state(state.id, %{
        config: %{"brightness" => "55", "temperature" => "3200"}
      })

    assert {:ok, refreshed} = Scenes.refresh_active_scenes_for_light_state(state.id)
    assert Enum.map(refreshed, & &1.id) == [scene.id]
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 55, kelvin: 3200}
  end

  test "activate_scene updates desired state for scene lights" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(state.id)
        }
      ])

    {:ok, diff, _updated} = Scenes.activate_scene(scene.id)

    assert diff[{:light, light1.id}][:brightness] == 40
    assert DesiredState.get(:light, light1.id)[:power] == :on
  end

  test "activate_scene materializes manual color states as xy desired state" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp", supports_color: true})

    {:ok, state} =
      Scenes.create_manual_light_state("Blue", %{
        "mode" => "color",
        "brightness" => "75",
        "hue" => "210",
        "saturation" => "60"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Color", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, diff, _updated} = Scenes.activate_scene(scene.id)
    {expected_x, expected_y} = Color.hs_to_xy(210, 60)

    assert diff[{:light, light.id}][:power] == :on
    assert diff[{:light, light.id}][:brightness] == 75
    assert_in_delta diff[{:light, light.id}][:x], expected_x, 0.0001
    assert_in_delta diff[{:light, light.id}][:y], expected_y, 0.0001
  end

  test "refresh_active_scene clears stale kelvin when a light moves from circadian to manual color" do
    room = insert_room()
    bridge = insert_bridge()

    light1 =
      insert_light(room, bridge, %{name: "Lamp 1", supports_color: true, supports_temp: true})

    light2 =
      insert_light(room, bridge, %{name: "Lamp 2", supports_color: true, supports_temp: true})

    {:ok, circadian} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    {:ok, color} =
      Scenes.create_manual_light_state("Blue", %{
        "mode" => "color",
        "brightness" => "75",
        "hue" => "210",
        "saturation" => "60"
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Mixed", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Circadian",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(circadian.id)
        }
      ])

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, _diff, _updated} = Scenes.activate_scene(scene.id)

    assert DesiredState.get(:light, light2.id)[:kelvin]

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Circadian", light_ids: [light1.id], light_state_id: to_string(circadian.id)},
        %{name: "Blue", light_ids: [light2.id], light_state_id: to_string(color.id)}
      ])

    {:ok, diff, _updated} = Scenes.refresh_active_scene(scene.id)
    {expected_x, expected_y} = Color.hs_to_xy(210, 60)

    assert diff[{:light, light2.id}][:brightness] == 75
    assert_in_delta diff[{:light, light2.id}][:x], expected_x, 0.0001
    assert_in_delta diff[{:light, light2.id}][:y], expected_y, 0.0001
    refute Map.has_key?(diff[{:light, light2.id}], :kelvin)

    desired = DesiredState.get(:light, light2.id)
    assert desired[:brightness] == 75
    assert_in_delta desired[:x], expected_x, 0.0001
    assert_in_delta desired[:y], expected_y, 0.0001
    refute Map.has_key?(desired, :kelvin)
  end

  test "apply_scene computes circadian brightness and kelvin for circadian light states" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Daylight", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "Etc/UTC"
      })

    {:ok, diff, _updated} =
      Scenes.apply_scene(scene, now: utc_dt("2026-03-08T12:00:00Z"))

    assert diff[{:light, light.id}][:brightness] == 90
    assert diff[{:light, light.id}][:kelvin] == 5000

    desired = DesiredState.get(:light, light.id)
    assert desired[:power] == :on
  end

  test "apply_scene replans when physical state still diverges even if desired state is already current" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    _ =
      Hueworks.Control.State.put(:light, light.id, %{
        power: :on,
        brightness: "10",
        kelvin: "2500"
      })

    {:ok, first_diff, _updated} = Scenes.apply_scene(scene)

    assert first_diff[{:light, light.id}] == %{power: :on, brightness: 40, kelvin: 3000}

    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 40, kelvin: 3000}

    {:ok, second_diff, _updated} = Scenes.apply_scene(scene)

    assert second_diff[{:light, light.id}] == %{brightness: 40, kelvin: 3000}
  end

  test "apply_scene preserves manual power-off latch during circadian reapply" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Daylight", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "Etc/UTC"
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})

    {:ok, diff, _updated} =
      Scenes.apply_scene(scene,
        preserve_power_latches: true,
        now: utc_dt("2026-03-08T12:00:00Z")
      )

    assert diff == %{{:light, light.id} => %{power: :off}}
    assert DesiredState.get(:light, light.id) == %{power: :off}
  end

  test "apply_scene keeps manually turned-on default-off light aligned to current scene state" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Daylight", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light.id],
          light_state_id: to_string(state.id),
          light_defaults: %{light.id => :force_off}
        }
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "Etc/UTC"
      })

    _ = DesiredState.put(:light, light.id, %{power: :on, brightness: 35, kelvin: 2400})

    {:ok, _diff, _updated} =
      Scenes.apply_scene(scene,
        preserve_power_latches: true,
        now: utc_dt("2026-03-08T12:00:00Z")
      )

    desired = DesiredState.get(:light, light.id)
    assert desired[:power] == :on
    assert desired[:brightness] == 90
    assert desired[:kelvin] == 5000
  end

  test "apply_scene clears previous power latch on fresh scene activation semantics" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Daylight", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "Etc/UTC"
      })

    _ = DesiredState.put(:light, light.id, %{power: :off})

    {:ok, _diff, _updated} =
      Scenes.apply_scene(scene,
        preserve_power_latches: false,
        now: utc_dt("2026-03-08T12:00:00Z")
      )

    desired = DesiredState.get(:light, light.id)
    assert desired[:power] == :on
    assert desired[:brightness] == 90
    assert desired[:kelvin] == 5000
  end

  test "apply_scene generates a trace by default when none is provided" do
    parent = self()
    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)

    on_exit(fn ->
      restore_app_env(:hueworks, :control_executor_enabled, original_enabled)
      restore_app_env(:hueworks, :control_executor_server, original_server)
    end)

    {:ok, _pid} =
      start_supervised(
        {Executor,
         name: :scene_trace_executor,
         dispatch_fun: fn action ->
           send(parent, {:dispatched, action})
           :ok
         end,
         bridge_rate_fun: fn _ -> 10 end}
      )

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, :scene_trace_executor)

    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})
    {:ok, state} = Scenes.create_manual_light_state("Soft", %{"brightness" => "40"})
    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    assert {:ok, _diff, _updated} = Scenes.apply_scene(scene)
    _ = Executor.tick(:scene_trace_executor, force: true)

    assert_receive {:dispatched, action}
    assert is_binary(action.trace_id)
    assert String.starts_with?(action.trace_id, "scene-#{scene.id}-")
    assert action.trace_source == "scenes.apply_scene"
    assert action.trace_room_id == room.id
    assert action.trace_scene_id == scene.id
  end

  test "active scene reapply preserves manual off latch after desired-state restart" do
    room = insert_room()
    bridge = insert_bridge()
    light = insert_light(room, bridge, %{name: "Lamp"})

    {:ok, state} =
      Scenes.create_light_state("Circadian", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Daylight", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Component 1", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "Etc/UTC"
      })

    {:ok, _} = ActiveScenes.set_active(scene)

    assert {:ok, %{power: :off}} =
             ManualControl.apply_power_action(room.id, [light.id], :off)

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      :ets.delete_all_objects(:hueworks_desired_state)
    end

    {:ok, _diff, _updated} =
      Scenes.apply_active_scene(scene, ActiveScenes.get_for_room(room.id),
        preserve_power_latches: true,
        occupied: false,
        now: utc_dt("2026-03-08T12:00:00Z")
      )

    assert DesiredState.get(:light, light.id) == %{power: :off}
  end

  defp utc_dt(iso8601) do
    {:ok, datetime, 0} = DateTime.from_iso8601(iso8601)
    datetime
  end

  test "apply_scene uses per-light default power while keeping shared manual values" do
    room = insert_room()
    bridge = insert_bridge()
    light1 = insert_light(room, bridge, %{name: "Lamp"})
    light2 = insert_light(room, bridge, %{name: "Ceiling"})

    {:ok, state} =
      Scenes.create_manual_light_state("Soft", %{"brightness" => "40", "temperature" => "3000"})

    {:ok, scene} = Scenes.create_scene(%{name: "Chill", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Component 1",
          light_ids: [light1.id, light2.id],
          light_state_id: to_string(state.id),
          light_defaults: %{light1.id => :force_on, light2.id => :force_off}
        }
      ])

    _ = Hueworks.Control.State.put(:light, light1.id, %{power: :off})

    _ =
      Hueworks.Control.State.put(:light, light2.id, %{
        power: :on,
        brightness: "25",
        kelvin: "2500"
      })

    {:ok, _diff, _updated} = Scenes.apply_scene(scene)

    desired_light1 = DesiredState.get(:light, light1.id)
    desired_light2 = DesiredState.get(:light, light2.id)

    assert desired_light1[:power] == :on
    assert desired_light1[:brightness] == 40
    assert desired_light1[:kelvin] == 3000

    assert desired_light2[:power] == :off
    refute Map.has_key?(desired_light2, :brightness)
    refute Map.has_key?(desired_light2, :kelvin)
  end
end
