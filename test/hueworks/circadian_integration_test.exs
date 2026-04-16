defmodule Hueworks.CircadianIntegrationTest do
  use HueworksWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hueworks.ActiveScenes
  alias Hueworks.AppSettings
  alias Hueworks.Control.{CircadianPoller, DesiredState, HuePayload, Planner, State, Z2MPayload}
  alias Hueworks.Repo
  alias Hueworks.Scenes
  alias Hueworks.Schemas.{ActiveScene, Bridge, Group, GroupLight, Light, Room}
  alias Hueworks.Subscription.HueEventStream.Mapper
  alias Hueworks.Subscription.Z2MEventStream.Connection.Handler, as: Z2MHandler

  setup do
    clear_ets(:hueworks_control_state)
    clear_ets(:hueworks_desired_state)

    :ok
  end

  test "circadian scene advances brightness during the pre-sunrise ramp before kelvin warms" do
    %{room: room, scene: scene, solo_hue: solo_hue} = setup_mixed_scene_fixture()

    {:ok, _} = ActiveScenes.set_active(scene)

    dawn_ramp = apply_scene_at(scene, "2026-03-31 05:00:00")
    sunrise = apply_scene_at(scene, "2026-03-31 06:00:00")
    actions = Planner.plan_room(room.id, sunrise.intent_diff)

    noon = apply_scene_at(scene, "2026-03-31 12:00:00")

    assert dawn_ramp.updated[{:light, solo_hue.id}] == %{power: :on, brightness: 37, kelvin: 2000}
    assert sunrise.updated[{:light, solo_hue.id}] == %{power: :on, brightness: 50, kelvin: 2000}
    assert noon.updated[{:light, solo_hue.id}] == %{power: :on, brightness: 90, kelvin: 4000}

    assert Map.fetch!(dawn_ramp.intent_diff, {:light, solo_hue.id})[:brightness] == 37
    assert Map.fetch!(sunrise.intent_diff, {:light, solo_hue.id})[:brightness] == 50
    assert Map.fetch!(noon.intent_diff, {:light, solo_hue.id})[:brightness] == 90

    assert Map.fetch!(dawn_ramp.intent_diff, {:light, solo_hue.id})[:kelvin] == 2000
    assert Map.fetch!(sunrise.intent_diff, {:light, solo_hue.id})[:kelvin] == 2000
    assert Map.fetch!(noon.intent_diff, {:light, solo_hue.id})[:kelvin] == 4000

    assert Enum.any?(actions, fn
             %{type: :group, desired: %{brightness: 50, kelvin: 2203}} -> true
             _ -> false
           end)

    assert Enum.any?(actions, fn
             %{type: :group, desired: %{brightness: 50, kelvin: 2000}} -> true
             _ -> false
           end)

    assert Enum.any?(actions, fn
             %{type: :light, id: id, desired: %{brightness: 50, kelvin: 2000}}
             when id == solo_hue.id ->
               true

             _ ->
               false
           end)
  end

  test "mixed Hue and Z2M circadian scene keeps member, group, and UI state aligned across low and warm kelvin phases",
       %{conn: conn} do
    fixture = setup_mixed_scene_fixture()
    %{room: room, scene: scene} = fixture

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, view, _html} = live(conn, "/lights")

    assert_round_trip(view, room.id, fixture, "2026-03-31 05:00:00", 37, 2000, 2000)
    assert_round_trip(view, room.id, fixture, "2026-03-31 12:00:00", 90, 4000, 3995)
  end

  test "z2m crossover-band events keep group and member UI aligned with hue values", %{conn: conn} do
    fixture = setup_mixed_scene_fixture("z2m-crossover")
    %{scene: scene} = fixture

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, view, _html} = live(conn, "/lights")

    local_time =
      time_for_round_tripped_kelvin!(
        fixture,
        {:group, fixture.hue_group.id},
        ~D[2026-03-31],
        &(&1 >= 2600 and &1 < 2700)
      )

    round_trip_at(view, fixture, local_time)

    {x, y} = Hueworks.Control.HomeAssistantPayload.extended_xy(2681)

    payload =
      Jason.encode!(%{
        "state" => "ON",
        "brightness" => 254,
        "color_mode" => "color_temp",
        "color" => %{"x" => x, "y" => y},
        "color_temp_kelvin" => 3479
      })

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_lower.source_id],
        payload,
        fixture.z2m_handler_state
      )

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_upper.source_id],
        payload,
        fixture.z2m_handler_state
      )

    baseline_html = render(view)
    baseline_hue_kelvin = html_value(baseline_html, "#group-temp-value-#{fixture.hue_group.id}")

    assert String.ends_with?(baseline_hue_kelvin, "K")
    assert baseline_hue_kelvin |> String.trim_trailing("K") |> String.to_integer() >= 2600
    assert baseline_hue_kelvin |> String.trim_trailing("K") |> String.to_integer() < 2700

    html = render(view)

    assert_value(html, "#group-temp-value-#{fixture.z2m_group.id}", "2681K")
    assert_value(html, "#light-temp-value-#{fixture.z2m_lower.id}", "2681K")
    assert_value(html, "#light-temp-value-#{fixture.z2m_upper.id}", "2681K")
  end

  test "echoed refresh updates do not clear the active scene" do
    %{room: room, scene: scene, solo_hue: solo_hue} = setup_mixed_scene_fixture()

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = apply_scene_at(scene, "2026-03-31 05:00:00")

    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)

    _ = State.put(:light, solo_hue.id, %{power: :on, brightness: 45, kelvin: 2000})

    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
  end

  test "active scene stays active through post-pending physical divergence" do
    %{room: room, scene: scene, solo_hue: solo_hue, hue_floor_a: hue_floor_a} =
      setup_mixed_scene_fixture()

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = apply_scene_at(scene, "2026-03-31 05:00:00")

    _ = State.put(:light, solo_hue.id, %{power: :on, brightness: 39, kelvin: 2000})
    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)

    _ = State.put(:light, hue_floor_a.id, %{power: :on, brightness: 37, kelvin: 2203})
    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)

    _ = State.put(:light, solo_hue.id, %{power: :on, brightness: 45, kelvin: 2000})
    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
  end

  test "brightness drift beyond prior tolerance does not clear the active scene" do
    %{room: room, scene: scene, solo_hue: solo_hue} = setup_mixed_scene_fixture("tolerance")

    {:ok, _} = ActiveScenes.set_active(scene)
    result = apply_scene_at(scene, "2026-03-31 05:00:00")
    desired = result.updated[{:light, solo_hue.id}]

    for delta <- -2..2 do
      _ =
        State.put(:light, solo_hue.id, %{
          power: :on,
          brightness: desired.brightness + delta,
          kelvin: desired.kelvin
        })

      assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
    end

    _ =
      State.put(:light, solo_hue.id, %{
        power: :on,
        brightness: desired.brightness + 3,
        kelvin: desired.kelvin
      })

    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
  end

  test "z2m group stays truthful when only some members are on during an active circadian scene",
       %{conn: conn} do
    fixture = setup_mixed_scene_fixture()
    %{room: room, scene: scene} = fixture

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, view, _html} = live(conn, "/lights")

    result = apply_scene_at(scene, "2026-03-31 05:00:00")
    actions = Planner.plan_room(room.id, result.intent_diff)
    desired = find_action_desired!(actions, :group, fixture.z2m_group.id)

    lower_payload =
      Jason.encode!(Z2MPayload.action_payload({:set_state, desired}, fixture.z2m_lower))

    off_payload = Jason.encode!(Z2MPayload.action_payload(:off, fixture.z2m_upper))

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_lower.source_id],
        lower_payload,
        fixture.z2m_handler_state
      )

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_upper.source_id],
        off_payload,
        fixture.z2m_handler_state
      )

    html = render(view)

    assert Map.take(State.get(:group, fixture.z2m_group.id), [:power, :brightness, :kelvin]) == %{
             power: :on,
             brightness: 37,
             kelvin: 2000
           }

    assert match?(%{power: :off}, State.get(:light, fixture.z2m_upper.id))
    assert_value(html, "#group-brightness-value-#{fixture.z2m_group.id}", "37%")
    assert_value(html, "#group-temp-value-#{fixture.z2m_group.id}", "2000K")
    assert has_element?(view, "#light-#{fixture.z2m_upper.id} button.hw-button-off", "On/Off")
    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
  end

  test "late z2m group echo does not overwrite mixed member truth during an active scene", %{
    conn: conn
  } do
    fixture = setup_mixed_scene_fixture("late-group")
    %{room: room, scene: scene} = fixture

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, view, _html} = live(conn, "/lights")

    result = apply_scene_at(scene, "2026-03-31 05:00:00")
    actions = Planner.plan_room(room.id, result.intent_diff)
    desired = find_action_desired!(actions, :group, fixture.z2m_group.id)

    lower_payload =
      Jason.encode!(Z2MPayload.action_payload({:set_state, desired}, fixture.z2m_lower))

    off_payload = Jason.encode!(Z2MPayload.action_payload(:off, fixture.z2m_upper))

    group_payload =
      Jason.encode!(Z2MPayload.action_payload({:set_state, desired}, fixture.z2m_group))

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_lower.source_id],
        lower_payload,
        fixture.z2m_handler_state
      )

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_upper.source_id],
        off_payload,
        fixture.z2m_handler_state
      )

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_group.source_id],
        group_payload,
        fixture.z2m_handler_state
      )

    html = render(view)

    assert Map.take(State.get(:group, fixture.z2m_group.id), [:power, :brightness, :kelvin]) == %{
             power: :on,
             brightness: 37,
             kelvin: 2000
           }

    assert match?(%{power: :off}, State.get(:light, fixture.z2m_upper.id))
    assert_value(html, "#group-temp-value-#{fixture.z2m_group.id}", "2000K")
    assert has_element?(view, "#light-#{fixture.z2m_upper.id} button.hw-button-off", "On/Off")
    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
  end

  test "circadian scene remains stable across the DST spring-forward boundary" do
    %{scene: scene, solo_hue: solo_hue} = setup_mixed_scene_fixture()

    before_gap = apply_scene_at(scene, "2026-03-08 01:30:00")
    after_gap = apply_scene_at(scene, "2026-03-08 03:30:00")

    assert before_gap.updated[{:light, solo_hue.id}] == %{
             power: :on,
             brightness: 10,
             kelvin: 2000
           }

    assert after_gap.updated[{:light, solo_hue.id}] == %{power: :on, brightness: 17, kelvin: 2000}
  end

  test "circadian scene remains monotonic across the DST fall-back boundary" do
    %{scene: scene, solo_hue: solo_hue} = setup_mixed_scene_fixture()

    before_fallback = apply_scene_at(scene, "2026-11-01 05:30:00")
    after_fallback = apply_scene_at(scene, "2026-11-01 06:30:00")

    before_state = before_fallback.updated[{:light, solo_hue.id}]
    after_state = after_fallback.updated[{:light, solo_hue.id}]

    assert before_state.brightness < after_state.brightness
    assert before_state.kelvin == 2000
    assert after_state.kelvin > 2000
  end

  test "kelvin boundaries flip Hue and Z2M UI values at the expected thresholds", %{conn: conn} do
    fixture = setup_mixed_scene_fixture()
    %{scene: scene} = fixture

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, view, _html} = live(conn, "/lights")

    hue_threshold =
      time_for_round_tripped_kelvin!(
        fixture,
        {:group, fixture.hue_group.id},
        ~D[2026-03-31],
        &(&1 > 2203)
      )

    hue_before = shift_local_time(hue_threshold, -60)

    z2m_threshold =
      time_for_round_tripped_kelvin!(
        fixture,
        {:group, fixture.z2m_group.id},
        ~D[2026-03-31],
        &(&1 >= 2700)
      )

    z2m_before = shift_local_time(z2m_threshold, -60)

    _ = round_trip_at(view, fixture, hue_before)
    hue_before_html = render(view)

    assert DesiredState.get(:light, fixture.solo_hue.id).kelvin <= 2205
    assert_value(hue_before_html, "#group-temp-value-#{fixture.hue_group.id}", "2203K")
    assert_value(hue_before_html, "#light-temp-value-#{fixture.hue_floor_a.id}", "2203K")

    _ = round_trip_at(view, fixture, hue_threshold)
    hue_threshold_html = render(view)

    assert DesiredState.get(:light, fixture.solo_hue.id).kelvin > 2200

    assert html_value(hue_threshold_html, "#group-temp-value-#{fixture.hue_group.id}") not in [
             "2203K",
             "2000K"
           ]

    assert html_value(hue_threshold_html, "#group-temp-value-#{fixture.hue_group.id}") ==
             html_value(hue_threshold_html, "#light-temp-value-#{fixture.hue_floor_a.id}")

    _ = round_trip_at(view, fixture, z2m_before)
    z2m_before_html = render(view)

    z2m_before_group = html_value(z2m_before_html, "#group-temp-value-#{fixture.z2m_group.id}")
    z2m_before_member = html_value(z2m_before_html, "#light-temp-value-#{fixture.z2m_lower.id}")

    assert String.trim_trailing(z2m_before_group, "K") |> String.to_integer() < 2700
    assert z2m_before_group == z2m_before_member

    _ = round_trip_at(view, fixture, z2m_threshold)
    z2m_threshold_html = render(view)

    z2m_threshold_group =
      html_value(z2m_threshold_html, "#group-temp-value-#{fixture.z2m_group.id}")

    z2m_threshold_member =
      html_value(z2m_threshold_html, "#light-temp-value-#{fixture.z2m_lower.id}")

    assert String.trim_trailing(z2m_threshold_group, "K") |> String.to_integer() >= 2700
    assert z2m_threshold_group == z2m_threshold_member
  end

  test "kelvin floor sweeps stay aligned across Hue and Z2M threshold edges", %{conn: conn} do
    fixture = setup_mixed_scene_fixture()

    {:ok, _} = ActiveScenes.set_active(fixture.scene)
    {:ok, view, _html} = live(conn, "/lights")

    hue_threshold =
      time_for_round_tripped_kelvin!(
        fixture,
        {:group, fixture.hue_group.id},
        ~D[2026-03-31],
        &(&1 > 2203)
      )

    for offset <- [-180, -120, -60, 0, 60, 120, 180] do
      local_time = shift_local_time(hue_threshold, offset)
      _ = round_trip_at(view, fixture, local_time)
      html = render(view)

      hue_group_kelvin = html_value(html, "#group-temp-value-#{fixture.hue_group.id}")
      hue_member_kelvin = html_value(html, "#light-temp-value-#{fixture.hue_floor_a.id}")

      assert hue_group_kelvin == hue_member_kelvin
      assert String.trim_trailing(hue_group_kelvin, "K") |> String.to_integer() >= 2203
    end

    z2m_threshold =
      time_for_round_tripped_kelvin!(
        fixture,
        {:group, fixture.z2m_group.id},
        ~D[2026-03-31],
        &(&1 >= 2700)
      )

    for offset <- [-180, -120, -60, 0, 60, 120, 180] do
      local_time = shift_local_time(z2m_threshold, offset)
      _ = round_trip_at(view, fixture, local_time)
      html = render(view)

      z2m_group_kelvin = html_value(html, "#group-temp-value-#{fixture.z2m_group.id}")
      z2m_member_kelvin = html_value(html, "#light-temp-value-#{fixture.z2m_lower.id}")

      assert z2m_group_kelvin == z2m_member_kelvin
    end
  end

  test "scene with mixed manual and circadian components keeps each component's intent distinct" do
    room = Repo.insert!(%Room{name: "Component Room"})

    hue_bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.50",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    manual_light =
      insert_light(room, hue_bridge, %{
        name: "Manual Lamp",
        display_name: "Manual Lamp",
        source: :hue,
        source_id: "manual-lamp",
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    circadian_light =
      insert_light(room, hue_bridge, %{
        name: "Circadian Lamp",
        display_name: "Circadian Lamp",
        source: :hue,
        source_id: "circadian-lamp",
        supports_temp: true,
        reported_min_kelvin: 2203,
        reported_max_kelvin: 6500
      })

    {:ok, manual_state} =
      Scenes.create_manual_light_state("Reading", %{"brightness" => "25", "temperature" => "2500"})

    {:ok, circadian_state} =
      Scenes.create_light_state("Adaptive", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 4000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 10_800,
        "brightness_mode_time_light" => 10_800
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Mixed Components", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Manual Component",
          light_ids: [manual_light.id],
          light_state_id: to_string(manual_state.id)
        },
        %{
          name: "Circadian Component",
          light_ids: [circadian_light.id],
          light_state_id: to_string(circadian_state.id)
        }
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York"
      })

    result = apply_scene_at(scene, "2026-03-31 12:00:00")

    assert result.updated[{:light, manual_light.id}] == %{
             power: :on,
             brightness: 25,
             kelvin: 2500
           }

    assert result.updated[{:light, circadian_light.id}] == %{
             power: :on,
             brightness: 90,
             kelvin: 4000
           }

    assert DesiredState.get(:light, manual_light.id) == %{
             power: :on,
             brightness: 25,
             kelvin: 2500
           }

    assert DesiredState.get(:light, circadian_light.id) == %{
             power: :on,
             brightness: 90,
             kelvin: 4000
           }
  end

  test "poller advances an active circadian scene using real elapsed time" do
    room = Repo.insert!(%Room{name: "Poller Room"})

    hue_bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.60",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      insert_light(room, hue_bridge, %{
        name: "Poller Lamp",
        display_name: "Poller Lamp",
        source: :hue,
        source_id: "poller-lamp",
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    now_local = DateTime.now!("America/New_York")

    sunrise =
      now_local
      |> DateTime.add(1, :second)
      |> DateTime.to_time()
      |> Time.truncate(:second)
      |> Time.to_iso8601()

    sunset =
      now_local
      |> DateTime.add(11, :second)
      |> DateTime.to_time()
      |> Time.truncate(:second)
      |> Time.to_iso8601()

    {:ok, state} =
      Scenes.create_light_state("Rapid Poller", :circadian, %{
        "sunrise_time" => sunrise,
        "sunset_time" => sunset,
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 2000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 5,
        "brightness_mode_time_light" => 5
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Rapid Poller Scene", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{name: "Rapid Component", light_ids: [light.id], light_state_id: to_string(state.id)}
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York"
      })

    {:ok, _} = ActiveScenes.set_active(scene)

    {:ok, _diff, _updated} =
      Scenes.apply_scene(scene, now: DateTime.utc_now())

    starting_desired = DesiredState.get(:light, light.id)
    starting_active = Repo.get_by!(ActiveScene, room_id: room.id)

    {:ok, pid} = CircadianPoller.start_link(name: nil, interval_ms: 100)

    assert eventually(fn ->
             current = DesiredState.get(:light, light.id)
             current != nil and current != starting_desired
           end)

    assert eventually(fn ->
             refreshed = Repo.get_by!(ActiveScene, room_id: room.id)
             DateTime.compare(refreshed.last_applied_at, starting_active.last_applied_at) == :gt
           end)

    GenServer.stop(pid)
  end

  test "compressed day progresses from brightness-only adaptation into warming kelvin" do
    room = Repo.insert!(%Room{name: "Compressed Day Room"})

    hue_bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.61",
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    light =
      insert_light(room, hue_bridge, %{
        name: "Compressed Day Lamp",
        display_name: "Compressed Day Lamp",
        source: :hue,
        source_id: "compressed-day-lamp",
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {:ok, state} =
      Scenes.create_light_state("Compressed Day", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "06:10:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 4000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 5,
        "brightness_mode_time_light" => 5
      })

    {:ok, scene} = Scenes.create_scene(%{name: "Compressed Day Scene", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Compressed Day Component",
          light_ids: [light.id],
          light_state_id: to_string(state.id)
        }
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York"
      })

    before_sunrise = apply_scene_at(scene, "2026-03-31 05:59:00")
    just_after_sunrise = apply_scene_at(scene, "2026-03-31 06:02:00")
    near_noon = apply_scene_at(scene, "2026-03-31 06:05:00")

    before_state = before_sunrise.updated[{:light, light.id}]
    after_state = just_after_sunrise.updated[{:light, light.id}]
    noon_state = near_noon.updated[{:light, light.id}]

    assert before_state.kelvin == 2000
    assert after_state.kelvin > before_state.kelvin
    assert noon_state.kelvin >= after_state.kelvin

    assert before_state.brightness < after_state.brightness
    assert after_state.brightness <= noon_state.brightness
  end

  test "lights reload button preserves active scene during echoed refresh updates", %{conn: conn} do
    %{room: room, scene: scene, solo_hue: solo_hue, hue_group: hue_group, z2m_group: z2m_group} =
      setup_mixed_scene_fixture("refresh")

    disable_bridges_for_refresh!([solo_hue.bridge_id, hue_group.bridge_id, z2m_group.bridge_id])

    {:ok, _} = ActiveScenes.set_active(scene)
    _ = apply_scene_at(scene, "2026-03-31 05:00:00")

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("button[phx-click=\"refresh\"]")
    |> render_click()

    assert render(view) =~ "Reloaded database snapshot"

    _ = State.put(:light, solo_hue.id, %{power: :on, brightness: 45, kelvin: 2000})
    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)
  end

  test "reload plus mixed z2m echoes keeps partial-member truth while the scene stays active", %{
    conn: conn
  } do
    fixture = setup_mixed_scene_fixture("reload-z2m")

    %{room: room, scene: scene, solo_hue: solo_hue, hue_group: hue_group, z2m_group: z2m_group} =
      fixture

    disable_bridges_for_refresh!([solo_hue.bridge_id, hue_group.bridge_id, z2m_group.bridge_id])

    {:ok, _} = ActiveScenes.set_active(scene)
    result = apply_scene_at(scene, "2026-03-31 05:00:00")
    actions = Planner.plan_room(room.id, result.intent_diff)
    desired = find_action_desired!(actions, :group, z2m_group.id)

    {:ok, view, _html} = live(conn, "/lights")

    view
    |> element("button[phx-click=\"refresh\"]")
    |> render_click()

    lower_payload =
      Jason.encode!(Z2MPayload.action_payload({:set_state, desired}, fixture.z2m_lower))

    off_payload = Jason.encode!(Z2MPayload.action_payload(:off, fixture.z2m_upper))

    group_payload =
      Jason.encode!(Z2MPayload.action_payload({:set_state, desired}, fixture.z2m_group))

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_lower.source_id],
        lower_payload,
        fixture.z2m_handler_state
      )

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_upper.source_id],
        off_payload,
        fixture.z2m_handler_state
      )

    {:ok, _state} =
      Z2MHandler.handle_message(
        ["zigbee2mqtt", fixture.z2m_group.source_id],
        group_payload,
        fixture.z2m_handler_state
      )

    html = render(view)

    assert %ActiveScene{} = ActiveScenes.get_for_room(room.id)

    assert Map.take(State.get(:group, fixture.z2m_group.id), [:power, :brightness, :kelvin]) == %{
             power: :on,
             brightness: 37,
             kelvin: 2000
           }

    assert match?(%{power: :off}, State.get(:light, fixture.z2m_upper.id))
    assert_value(html, "#group-temp-value-#{fixture.z2m_group.id}", "2000K")
    assert has_element?(view, "#light-#{fixture.z2m_upper.id} button.hw-button-off", "On/Off")
  end

  test "sequential Hue grouped-light updates never overwrite member UI state", %{conn: conn} do
    fixture = setup_mixed_scene_fixture()
    %{room: room, scene: scene} = fixture

    {:ok, _} = ActiveScenes.set_active(scene)
    {:ok, view, _html} = live(conn, "/lights")

    _ = round_trip_at(view, fixture, "2026-03-31 05:00:00")
    low_html = render(view)

    assert_value(low_html, "#group-temp-value-#{fixture.hue_group.id}", "2203K")
    assert_value(low_html, "#light-temp-value-#{fixture.hue_floor_a.id}", "2203K")
    assert_value(low_html, "#light-temp-value-#{fixture.hue_floor_b.id}", "2203K")

    warm_result = apply_scene_at(scene, "2026-03-31 12:00:00")
    warm_actions = Planner.plan_room(room.id, warm_result.intent_diff)

    simulate_hue_group_action(warm_actions, fixture.hue_group, fixture.hue_mapper_state)
    group_only_html = render(view)

    assert_value(group_only_html, "#group-temp-value-#{fixture.hue_group.id}", "4000K")
    assert_value(group_only_html, "#light-temp-value-#{fixture.hue_floor_a.id}", "4000K")
    assert_value(group_only_html, "#light-temp-value-#{fixture.hue_floor_b.id}", "4000K")

    simulate_hue_group_members(
      warm_actions,
      fixture.hue_group,
      [fixture.hue_floor_a, fixture.hue_floor_b],
      fixture.hue_mapper_state
    )

    member_html = render(view)

    assert_value(member_html, "#group-temp-value-#{fixture.hue_group.id}", "4000K")
    assert_value(member_html, "#light-temp-value-#{fixture.hue_floor_a.id}", "4000K")
    assert_value(member_html, "#light-temp-value-#{fixture.hue_floor_b.id}", "4000K")
  end

  test "multiple active rooms stay isolated across clears and circadian updates" do
    fixture_a = setup_mixed_scene_fixture("A")
    fixture_b = setup_mixed_scene_fixture("B")

    {:ok, _} = ActiveScenes.set_active(fixture_a.scene)
    {:ok, _} = ActiveScenes.set_active(fixture_b.scene)

    dawn_a = apply_scene_at(fixture_a.scene, "2026-03-31 05:00:00")
    noon_b = apply_scene_at(fixture_b.scene, "2026-03-31 12:00:00")

    assert dawn_a.updated[{:light, fixture_a.solo_hue.id}] == %{
             power: :on,
             brightness: 37,
             kelvin: 2000
           }

    assert noon_b.updated[{:light, fixture_b.solo_hue.id}] == %{
             power: :on,
             brightness: 90,
             kelvin: 4000
           }

    _ = State.put(:light, fixture_a.solo_hue.id, %{power: :on, brightness: 45, kelvin: 2000})

    assert %ActiveScene{scene_id: scene_a_id} = ActiveScenes.get_for_room(fixture_a.room.id)
    assert scene_a_id == fixture_a.scene.id
    assert %ActiveScene{scene_id: scene_id} = ActiveScenes.get_for_room(fixture_b.room.id)
    assert scene_id == fixture_b.scene.id

    assert DesiredState.get(:light, fixture_b.solo_hue.id) == %{
             power: :on,
             brightness: 90,
             kelvin: 4000
           }
  end

  defp setup_mixed_scene_fixture(suffix \\ "") do
    room_suffix = if suffix == "", do: "", else: " #{suffix}"
    id_suffix = if suffix == "", do: "", else: "-#{suffix}"

    room = Repo.insert!(%Room{name: "Main Floor#{room_suffix}"})

    hue_bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Hue Bridge#{room_suffix}",
        host: if(suffix == "", do: "10.0.0.40", else: "10.0.0.40#{id_suffix}"),
        credentials: %{"api_key" => "key"},
        enabled: true
      })

    z2m_bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M Bridge#{room_suffix}",
        host: if(suffix == "", do: "10.0.0.80", else: "10.0.0.80#{id_suffix}"),
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    solo_hue =
      insert_light(room, hue_bridge, %{
        name: "Bar Accent#{room_suffix}",
        display_name: "Bar Accent#{room_suffix}",
        source: :hue,
        source_id: "hue-bar-accent#{id_suffix}",
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    hue_floor_a =
      insert_light(room, hue_bridge, %{
        name: "Hue Floor A#{room_suffix}",
        display_name: "Hue Floor A#{room_suffix}",
        source: :hue,
        source_id: "hue-floor-a#{id_suffix}",
        supports_temp: true,
        reported_min_kelvin: 2203,
        reported_max_kelvin: 6500
      })

    hue_floor_b =
      insert_light(room, hue_bridge, %{
        name: "Hue Floor B#{room_suffix}",
        display_name: "Hue Floor B#{room_suffix}",
        source: :hue,
        source_id: "hue-floor-b#{id_suffix}",
        supports_temp: true,
        reported_min_kelvin: 2203,
        reported_max_kelvin: 6500
      })

    hue_group =
      insert_group(room, hue_bridge, %{
        name: "Hue Floor Group#{room_suffix}",
        display_name: "Hue Floor Group#{room_suffix}",
        source: :hue,
        source_id: "hue-group-1#{id_suffix}",
        supports_temp: true,
        reported_min_kelvin: 2203,
        reported_max_kelvin: 6500
      })

    link_group(hue_group, [hue_floor_a, hue_floor_b])

    z2m_lower =
      insert_light(room, z2m_bridge, %{
        name: "Bar Lower Cabinet Lights#{room_suffix}",
        display_name: "Bar Lower Cabinet Lights#{room_suffix}",
        source: :z2m,
        source_id: "bar_lower_cabinet#{id_suffix}",
        supports_temp: true,
        reported_min_kelvin: 2288,
        reported_max_kelvin: 6500,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    z2m_upper =
      insert_light(room, z2m_bridge, %{
        name: "Bar Upper Cabinet Lights#{room_suffix}",
        display_name: "Bar Upper Cabinet Lights#{room_suffix}",
        source: :z2m,
        source_id: "bar_upper_cabinet#{id_suffix}",
        supports_temp: true,
        reported_min_kelvin: 2288,
        reported_max_kelvin: 6500,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    z2m_group =
      insert_group(room, z2m_bridge, %{
        name: "Bar Cabinet Lights#{room_suffix}",
        display_name: "Bar Cabinet Lights#{room_suffix}",
        source: :z2m,
        source_id: "bar_cabinet_group#{id_suffix}",
        supports_temp: true,
        reported_min_kelvin: 2288,
        reported_max_kelvin: 6500,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true,
        metadata: %{"members" => [z2m_lower.source_id, z2m_upper.source_id]}
      })

    link_group(z2m_group, [z2m_lower, z2m_upper])

    {:ok, circadian_state} =
      Scenes.create_light_state("Integration Circadian#{room_suffix}", :circadian, %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 4000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 10_800,
        "brightness_mode_time_light" => 10_800
      })

    {:ok, scene} =
      Scenes.create_scene(%{name: "Circadian Integration#{room_suffix}", room_id: room.id})

    {:ok, _} =
      Scenes.replace_scene_components(scene, [
        %{
          name: "Mixed Circadian",
          light_ids: [solo_hue.id, hue_floor_a.id, hue_floor_b.id, z2m_lower.id, z2m_upper.id],
          light_state_id: to_string(circadian_state.id)
        }
      ])

    {:ok, _} =
      AppSettings.upsert_global(%{
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: "America/New_York"
      })

    %{
      room: room,
      scene: scene,
      solo_hue: solo_hue,
      hue_floor_a: hue_floor_a,
      hue_floor_b: hue_floor_b,
      hue_group: hue_group,
      z2m_lower: z2m_lower,
      z2m_upper: z2m_upper,
      z2m_group: z2m_group,
      hue_mapper_state:
        hue_mapper_state(hue_bridge, [solo_hue, hue_floor_a, hue_floor_b], [hue_group]),
      z2m_handler_state: z2m_handler_state(z2m_bridge)
    }
  end

  defp assert_round_trip(
         view,
         room_id,
         fixture,
         local_time,
         expected_brightness,
         expected_desired_kelvin,
         expected_z2m_display_kelvin
       ) do
    result = apply_scene_at(fixture.scene, local_time)
    actions = Planner.plan_room(room_id, result.intent_diff)

    assert Enum.any?(actions)

    assert DesiredState.get(:light, fixture.solo_hue.id) == %{
             power: :on,
             brightness: expected_brightness,
             kelvin: expected_desired_kelvin
           }

    assert_scene_actions(actions, fixture, expected_brightness, expected_desired_kelvin)

    simulate_hue_action(actions, fixture.solo_hue, fixture.hue_mapper_state)
    simulate_hue_group_action(actions, fixture.hue_group, fixture.hue_mapper_state)

    simulate_z2m_group_members(
      actions,
      fixture.z2m_group,
      [fixture.z2m_lower, fixture.z2m_upper],
      fixture.z2m_handler_state
    )

    html = render(view)

    assert_value(
      html,
      "#light-brightness-value-#{fixture.solo_hue.id}",
      "#{expected_brightness}%"
    )

    assert_value(html, "#light-temp-value-#{fixture.solo_hue.id}", "#{expected_desired_kelvin}K")

    expected_hue_group_kelvin =
      if expected_desired_kelvin < 2203, do: 2203, else: expected_desired_kelvin

    assert_value(
      html,
      "#group-brightness-value-#{fixture.hue_group.id}",
      "#{expected_brightness}%"
    )

    assert_value(
      html,
      "#group-temp-value-#{fixture.hue_group.id}",
      "#{expected_hue_group_kelvin}K"
    )

    assert_value(
      html,
      "#light-temp-value-#{fixture.hue_floor_a.id}",
      "#{expected_hue_group_kelvin}K"
    )

    assert_value(
      html,
      "#light-temp-value-#{fixture.hue_floor_b.id}",
      "#{expected_hue_group_kelvin}K"
    )

    assert_value(
      html,
      "#group-brightness-value-#{fixture.z2m_group.id}",
      "#{expected_brightness}%"
    )

    assert_value(
      html,
      "#group-temp-value-#{fixture.z2m_group.id}",
      "#{expected_z2m_display_kelvin}K"
    )

    assert_value(
      html,
      "#light-temp-value-#{fixture.z2m_lower.id}",
      "#{expected_z2m_display_kelvin}K"
    )

    assert_value(
      html,
      "#light-temp-value-#{fixture.z2m_upper.id}",
      "#{expected_z2m_display_kelvin}K"
    )

    assert State.get(:group, fixture.hue_group.id) == %{
             power: :on,
             brightness: expected_brightness,
             kelvin: expected_hue_group_kelvin
           }

    assert State.get(:group, fixture.z2m_group.id) == %{
             power: :on,
             brightness: expected_brightness,
             kelvin: expected_z2m_display_kelvin
           }
  end

  defp assert_scene_actions(actions, fixture, expected_brightness, expected_kelvin) do
    expected_hue_group_kelvin = if expected_kelvin < 2203, do: 2203, else: expected_kelvin

    assert Enum.any?(actions, fn
             %{
               type: :light,
               id: id,
               desired: %{brightness: ^expected_brightness, kelvin: ^expected_kelvin, power: :on}
             }
             when id == fixture.solo_hue.id ->
               true

             _ ->
               false
           end)

    assert Enum.any?(actions, fn
             %{
               type: :group,
               id: id,
               desired: %{
                 brightness: ^expected_brightness,
                 kelvin: ^expected_hue_group_kelvin,
                 power: :on
               }
             }
             when id == fixture.hue_group.id ->
               true

             _ ->
               false
           end)

    assert Enum.any?(actions, fn
             %{
               type: :group,
               id: id,
               desired: %{brightness: ^expected_brightness, kelvin: ^expected_kelvin, power: :on}
             }
             when id == fixture.z2m_group.id ->
               true

             _ ->
               false
           end)
  end

  defp simulate_hue_action(actions, light, mapper_state) do
    desired = find_action_desired!(actions, :light, light.id)

    Mapper.handle_resource(
      %{
        "type" => "light",
        "id_v1" => "/lights/#{light.source_id}",
        "on" => %{"on" => true},
        "dimming" => %{"brightness" => desired.brightness * 1.0},
        "color_temperature" => %{"mirek" => HuePayload.kelvin_to_mired(desired.kelvin)}
      },
      mapper_state
    )
  end

  defp simulate_hue_group_action(actions, group, mapper_state) do
    desired = find_action_desired!(actions, :group, group.id)

    Mapper.handle_resource(
      %{
        "type" => "grouped_light",
        "id_v1" => "/groups/#{group.source_id}",
        "on" => %{"on" => true},
        "dimming" => %{"brightness" => desired.brightness * 1.0},
        "color_temperature" => %{"mirek" => HuePayload.kelvin_to_mired(desired.kelvin)}
      },
      mapper_state
    )
  end

  defp simulate_hue_group_members(actions, group, lights, mapper_state) do
    desired = find_action_desired!(actions, :group, group.id)

    Enum.each(lights, fn light ->
      Mapper.handle_resource(
        %{
          "type" => "light",
          "id_v1" => "/lights/#{light.source_id}",
          "on" => %{"on" => true},
          "dimming" => %{"brightness" => desired.brightness * 1.0},
          "color_temperature" => %{"mirek" => HuePayload.kelvin_to_mired(desired.kelvin)}
        },
        mapper_state
      )
    end)
  end

  defp simulate_z2m_group_members(actions, group, lights, handler_state) do
    desired = find_action_desired!(actions, :group, group.id)

    Enum.each(lights, fn light ->
      payload =
        desired
        |> then(&Z2MPayload.action_payload({:set_state, &1}, light))
        |> Jason.encode!()

      {:ok, _state} =
        Z2MHandler.handle_message(["zigbee2mqtt", light.source_id], payload, handler_state)
    end)
  end

  defp hue_mapper_state(bridge, lights, groups) do
    {group_light_ids, group_lights} = Mapper.load_group_maps(bridge.id)

    %{
      lights_by_id: Map.new(lights, &{&1.source_id, %{id: &1.id}}),
      groups_by_id: Map.new(groups, &{&1.source_id, %{id: &1.id}}),
      group_light_ids: group_light_ids,
      group_lights: group_lights
    }
  end

  defp z2m_handler_state(bridge) do
    {:ok, state} = Z2MHandler.init([bridge.id, "zigbee2mqtt"])
    state
  end

  defp apply_scene_at(scene, local_time) do
    {:ok, result_diff, result_updated} = Scenes.apply_scene(scene, now: ny_dt(local_time))

    %{
      intent_diff: result_diff,
      updated: result_updated
    }
  end

  defp round_trip_at(view, fixture, local_time) do
    result = apply_scene_at(fixture.scene, local_time)
    actions = Planner.plan_room(fixture.room.id, result.intent_diff)

    if Enum.any?(actions, &(&1.type == :light and &1.id == fixture.solo_hue.id)) do
      simulate_hue_action(actions, fixture.solo_hue, fixture.hue_mapper_state)
    end

    if Enum.any?(actions, &(&1.type == :group and &1.id == fixture.hue_group.id)) do
      simulate_hue_group_action(actions, fixture.hue_group, fixture.hue_mapper_state)

      simulate_hue_group_members(
        actions,
        fixture.hue_group,
        [fixture.hue_floor_a, fixture.hue_floor_b],
        fixture.hue_mapper_state
      )
    end

    if Enum.any?(actions, &(&1.type == :group and &1.id == fixture.z2m_group.id)) do
      simulate_z2m_group_members(
        actions,
        fixture.z2m_group,
        [fixture.z2m_lower, fixture.z2m_upper],
        fixture.z2m_handler_state
      )
    end

    %{result: result, actions: actions, html: render(view)}
  end

  defp find_action_desired!(actions, type, id) do
    actions
    |> Enum.find(fn action -> action.type == type and action.id == id end)
    |> case do
      %{desired: desired} -> desired
      nil -> flunk("missing #{type} action for #{inspect(id)} in #{inspect(actions)}")
    end
  end

  defp assert_value(html, selector, expected) do
    assert html_value(html, selector) == expected
  end

  defp html_value(html, selector) do
    html
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Floki.text(sep: " ")
    |> String.trim()
  end

  defp ny_dt(local_time) do
    {:ok, naive} = NaiveDateTime.from_iso8601(local_time)
    DateTime.from_naive!(naive, "America/New_York") |> DateTime.shift_zone!("Etc/UTC")
  end

  defp shift_local_time(local_time, seconds) do
    {:ok, naive} = NaiveDateTime.from_iso8601(local_time)
    naive |> NaiveDateTime.add(seconds, :second) |> NaiveDateTime.to_iso8601()
  end

  defp time_for_round_tripped_kelvin!(fixture, {type, id}, date, matcher)
       when is_function(matcher, 1) do
    Enum.find_value(0..1_439, fn minute ->
      local_time =
        date
        |> NaiveDateTime.new!(~T[00:00:00])
        |> NaiveDateTime.add(minute * 60, :second)
        |> NaiveDateTime.to_iso8601()

      result = apply_scene_at(fixture.scene, local_time)
      actions = Planner.plan_room(fixture.room.id, result.intent_diff)

      if Enum.empty?(actions) do
        nil
      else
        if Enum.any?(actions, &(&1.type == :light and &1.id == fixture.solo_hue.id)) do
          simulate_hue_action(actions, fixture.solo_hue, fixture.hue_mapper_state)
        end

        if Enum.any?(actions, &(&1.type == :group and &1.id == fixture.hue_group.id)) do
          simulate_hue_group_action(actions, fixture.hue_group, fixture.hue_mapper_state)

          simulate_hue_group_members(
            actions,
            fixture.hue_group,
            [fixture.hue_floor_a, fixture.hue_floor_b],
            fixture.hue_mapper_state
          )
        end

        if Enum.any?(actions, &(&1.type == :group and &1.id == fixture.z2m_group.id)) do
          simulate_z2m_group_members(
            actions,
            fixture.z2m_group,
            [fixture.z2m_lower, fixture.z2m_upper],
            fixture.z2m_handler_state
          )
        end

        case State.get(type, id) do
          %{kelvin: kelvin} when is_number(kelvin) ->
            if matcher.(kelvin), do: local_time

          _ ->
            nil
        end
      end
    end) || flunk("no local time found for round-tripped #{type} #{id}")
  end

  defp insert_light(room, bridge, attrs) do
    defaults = %{
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{},
      enabled: true
    }

    Repo.insert!(struct(Light, Map.merge(defaults, attrs)))
  end

  defp insert_group(room, bridge, attrs) do
    defaults = %{
      bridge_id: bridge.id,
      room_id: room.id,
      metadata: %{},
      enabled: true
    }

    Repo.insert!(struct(Group, Map.merge(defaults, attrs)))
  end

  defp link_group(group, lights) do
    Enum.each(lights, fn light ->
      Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    end)
  end

  defp clear_ets(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end
  end

  defp disable_bridges_for_refresh!(bridge_ids) do
    bridge_ids
    |> Enum.uniq()
    |> Enum.each(fn bridge_id ->
      bridge_id
      |> then(&Repo.get!(Bridge, &1))
      |> Ecto.Changeset.change(enabled: false)
      |> Repo.update!()
    end)
  end

  defp eventually(fun, attempts \\ 40)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(50)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
