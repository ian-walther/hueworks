defmodule Hueworks.HardwareSmoke do
  @moduledoc false

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hueworks.{Groups, Picos, Repo, Scenes}
  alias Hueworks.Control.Executor
  alias Hueworks.Control.{DesiredState, LightStateSemantics, State}
  alias Hueworks.Schemas.{Light, PicoButton, PicoDevice, Room, Scene}

  @brightness_tolerance 2
  @temperature_mired_tolerance 1

  def run!(scenario_name, opts \\ []) when is_binary(scenario_name) and is_list(opts) do
    case scenario_name do
      "kitchen_accent_pico" -> run_kitchen_accent_pico!(opts)
      "kitchen_accent_lower_repeat" -> run_kitchen_accent_lower_repeat!(opts)
      other -> raise ArgumentError, "unknown hardware smoke scenario: #{inspect(other)}"
    end
  end

  def run_kitchen_accent_lower_repeat!(opts \\ []) do
    scenario = resolve_kitchen_accent_pico!()
    cycles = Keyword.get(opts, :loops, 10)
    timeout_ms = Keyword.get(opts, :timeout_ms, 8_000)
    poll_ms = Keyword.get(opts, :poll_ms, 250)
    settle_ms = Keyword.get(opts, :settle_ms, 1_000)
    dry_run? = Keyword.get(opts, :dry_run, false)

    print_lower_repeat_summary(scenario, cycles, timeout_ms, poll_ms, settle_ms)

    if dry_run? do
      :ok
    else
      wait_for_physical_state!(scenario.all_light_ids, timeout_ms, poll_ms)
      wait_for_executor_idle!("initial idle", timeout_ms, poll_ms)

      baseline = activate_and_capture_baseline!(scenario, timeout_ms, poll_ms, settle_ms)

      Enum.each(1..cycles, fn cycle ->
        info("\\n=== Lower Cycle #{cycle}/#{cycles} ===")

        run_step!(
          %{
            name: "lower_off_cycle_#{cycle}",
            button: scenario.buttons.lower_off,
            target_light_ids: scenario.groups.lower.light_ids,
            expected_desired: off_desired_states(scenario.groups.lower.light_ids)
          },
          scenario,
          timeout_ms,
          poll_ms,
          settle_ms
        )

        run_step!(
          %{
            name: "lower_on_cycle_#{cycle}",
            button: scenario.buttons.lower_on,
            target_light_ids: scenario.groups.lower.light_ids,
            expected_desired: subset_desired_states(baseline, scenario.groups.lower.light_ids)
          },
          scenario,
          timeout_ms,
          poll_ms,
          settle_ms
        )
      end)

      wait_for_executor_idle!("final idle", timeout_ms, poll_ms)
      sleep_settle(settle_ms)

      info("\\nHardware smoke passed for kitchen_accent_lower_repeat.")
      :ok
    end
  end

  def run_kitchen_accent_pico!(opts \\ []) do
    scenario = resolve_kitchen_accent_pico!()
    loops = Keyword.get(opts, :loops, 3)
    timeout_ms = Keyword.get(opts, :timeout_ms, 8_000)
    poll_ms = Keyword.get(opts, :poll_ms, 250)
    settle_ms = Keyword.get(opts, :settle_ms, 1_000)
    dry_run? = Keyword.get(opts, :dry_run, false)

    print_scenario_summary(scenario, loops, timeout_ms, poll_ms, settle_ms)

    if dry_run? do
      :ok
    else
      wait_for_physical_state!(scenario.all_light_ids, timeout_ms, poll_ms)
      wait_for_executor_idle!("initial idle", timeout_ms, poll_ms)

      Enum.each(1..loops, fn loop_index ->
        info("\\n=== Loop #{loop_index}/#{loops} ===")
        baseline = activate_and_capture_baseline!(scenario, timeout_ms, poll_ms, settle_ms)
        steps = scenario_steps(scenario, baseline)
        Enum.each(steps, &run_step!(&1, scenario, timeout_ms, poll_ms, settle_ms))
      end)

      wait_for_executor_idle!("final idle", timeout_ms, poll_ms)
      sleep_settle(settle_ms)

      info("\\nHardware smoke passed for kitchen_accent_pico.")
      :ok
    end
  end

  defp resolve_kitchen_accent_pico! do
    room = Repo.get_by!(Room, name: "Main Floor")
    scene = Repo.get_by!(Scene, room_id: room.id, name: "All Auto")

    device =
      PicoDevice
      |> Repo.get_by!(room_id: room.id, name: "Kitchen / Accent PIco")
      |> Repo.preload(buttons: from(pb in PicoButton, order_by: [asc: pb.button_number]))

    control_groups = Picos.control_groups(device)

    overhead_group =
      Enum.find(control_groups, &(&1["name"] == "Overhead")) ||
        raise "missing Overhead control group"

    lower_group =
      Enum.find(control_groups, &(&1["name"] == "Lower")) || raise "missing Lower control group"

    overhead_light_ids = expand_control_group_light_ids(room.id, overhead_group)
    lower_light_ids = expand_control_group_light_ids(room.id, lower_group)
    all_light_ids = Enum.uniq(overhead_light_ids ++ lower_light_ids)

    %{
      room: room,
      scene: scene,
      device: device,
      assert_keys: [:power],
      groups: %{
        overhead: %{
          id: overhead_group["id"],
          name: overhead_group["name"],
          light_ids: overhead_light_ids
        },
        lower: %{id: lower_group["id"], name: lower_group["name"], light_ids: lower_light_ids}
      },
      all_light_ids: all_light_ids,
      buttons: %{
        overhead_on: find_single_control_group_button!(device, "turn_on", overhead_group["id"]),
        overhead_off:
          find_single_control_group_button!(device, "turn_off", overhead_group["id"]),
        lower_on: find_single_control_group_button!(device, "turn_on", lower_group["id"]),
        lower_off: find_single_control_group_button!(device, "turn_off", lower_group["id"]),
        all_toggle: find_all_control_groups_button!(device, "toggle_any_on")
      },
      lights: load_lights_by_id(all_light_ids)
    }
  end

  defp scenario_steps(scenario, baseline) do
    [
      %{
        name: "overhead_off",
        button: scenario.buttons.overhead_off,
        target_light_ids: scenario.groups.overhead.light_ids,
        expected_desired: off_desired_states(scenario.groups.overhead.light_ids)
      },
      %{
        name: "overhead_on",
        button: scenario.buttons.overhead_on,
        target_light_ids: scenario.groups.overhead.light_ids,
        expected_desired: subset_desired_states(baseline, scenario.groups.overhead.light_ids)
      },
      %{
        name: "lower_off",
        button: scenario.buttons.lower_off,
        target_light_ids: scenario.groups.lower.light_ids,
        expected_desired: off_desired_states(scenario.groups.lower.light_ids)
      },
      %{
        name: "lower_on",
        button: scenario.buttons.lower_on,
        target_light_ids: scenario.groups.lower.light_ids,
        expected_desired: subset_desired_states(baseline, scenario.groups.lower.light_ids)
      },
      %{
        name: "toggle_all_off",
        button: scenario.buttons.all_toggle,
        target_light_ids: scenario.all_light_ids,
        expected_desired: off_desired_states(scenario.all_light_ids)
      },
      %{
        name: "toggle_all_on",
        button: scenario.buttons.all_toggle,
        target_light_ids: scenario.all_light_ids,
        expected_desired: subset_desired_states(baseline, scenario.all_light_ids)
      }
    ]
  end

  defp activate_and_capture_baseline!(scenario, timeout_ms, poll_ms, settle_ms) do
    info("Activating scene #{inspect(scenario.scene.name)} for #{inspect(scenario.room.name)}")

    case Scenes.activate_scene(scenario.scene.id, trace: smoke_trace("activate_scene")) do
      {:ok, _diff, _updated} -> :ok
      other -> raise "failed to activate scene: #{inspect(other)}"
    end

    wait_for_convergence!(
      "activate_scene",
      scenario.all_light_ids,
      timeout_ms,
      poll_ms,
      scenario.lights,
      scenario.assert_keys
    )

    baseline = capture_desired_states(scenario.all_light_ids)
    assert_scene_active!(scenario)

    assert_expected_desired!(
      "baseline",
      baseline,
      timeout_ms,
      poll_ms,
      scenario.lights,
      scenario.assert_keys
    )

    wait_for_executor_idle!("activate_scene executor idle", timeout_ms, poll_ms)
    sleep_settle(settle_ms)
    baseline
  end

  defp run_step!(step, scenario, timeout_ms, poll_ms, settle_ms) do
    info(
      "Pressing #{step.name} via button #{step.button.button_number} (source #{step.button.source_id})"
    )

    case Picos.handle_button_press(scenario.device.bridge_id, step.button.source_id) do
      :handled -> :ok
      other -> raise "#{step.name} did not handle cleanly: #{inspect(other)}"
    end

    assert_scene_active!(scenario)

    assert_expected_desired!(
      step.name,
      step.expected_desired,
      timeout_ms,
      poll_ms,
      scenario.lights,
      scenario.assert_keys
    )

    wait_for_convergence!(
      step.name,
      step.target_light_ids,
      timeout_ms,
      poll_ms,
      scenario.lights,
      scenario.assert_keys
    )

    wait_for_executor_idle!("#{step.name} executor idle", timeout_ms, poll_ms)
    sleep_settle(settle_ms)
  end

  defp wait_for_physical_state!(light_ids, timeout_ms, poll_ms) do
    wait_until!("physical bootstrap", timeout_ms, poll_ms, fn ->
      case Enum.reject(light_ids, &(State.get(:light, &1) != nil)) do
        [] -> :ok
        missing -> {:retry, "missing physical state for #{inspect(missing)}"}
      end
    end)
  end

  defp assert_scene_active!(scenario) do
    case Hueworks.ActiveScenes.get_for_room(scenario.room.id) do
      %{scene_id: scene_id} when scene_id == scenario.scene.id -> :ok
      other -> raise "active scene changed unexpectedly: #{inspect(other)}"
    end
  end

  defp assert_expected_desired!(label, expected_by_light, timeout_ms, poll_ms, lights_by_id, keys) do
    wait_until!("#{label} desired-state update", timeout_ms, poll_ms, fn ->
      divergences = desired_divergences(expected_by_light, keys)

      case divergences do
        [] -> :ok
        _ -> {:retry, format_divergences(divergences, lights_by_id)}
      end
    end)
  end

  defp wait_for_convergence!(label, light_ids, timeout_ms, poll_ms, lights_by_id, keys) do
    wait_until!("#{label} convergence", timeout_ms, poll_ms, fn ->
      divergences = convergence_divergences(light_ids, keys)

      case divergences do
        [] -> :ok
        _ -> {:retry, format_divergences(divergences, lights_by_id)}
      end
    end)
  end

  defp wait_for_executor_idle!(label, timeout_ms, poll_ms) do
    wait_until!(label, timeout_ms, poll_ms, fn ->
      case Executor.stats() do
        %{queues: queues} = stats ->
          pending = Enum.reject(queues, fn {_bridge_id, len} -> len == 0 end)

          if pending == [] do
            :ok
          else
            {:retry, "executor pending=#{inspect(pending)} stats=#{inspect(stats)}"}
          end

        other ->
          {:retry, "unexpected executor stats=#{inspect(other)}"}
      end
    end)
  end

  defp wait_until!(label, timeout_ms, poll_ms, fun) do
    started_at = System.monotonic_time(:millisecond)
    do_wait_until(label, started_at, timeout_ms, poll_ms, nil, fun)
  end

  defp do_wait_until(label, started_at, timeout_ms, poll_ms, last_detail, fun) do
    case fun.() do
      :ok ->
        elapsed = System.monotonic_time(:millisecond) - started_at
        info("  #{label} passed in #{elapsed}ms")
        :ok

      {:retry, detail} ->
        elapsed = System.monotonic_time(:millisecond) - started_at

        if elapsed >= timeout_ms do
          raise "#{label} timed out after #{elapsed}ms\\n#{detail || last_detail || "no detail"}"
        else
          Process.sleep(poll_ms)
          do_wait_until(label, started_at, timeout_ms, poll_ms, detail, fun)
        end
    end
  end

  defp desired_divergences(expected_by_light, keys) do
    expected_by_light
    |> Enum.flat_map(fn {light_id, expected} ->
      expected = select_keys(expected, keys)
      actual = DesiredState.get(:light, light_id) |> Kernel.||(%{}) |> select_keys(keys)

      keys =
        LightStateSemantics.diverging_keys(expected, actual,
          brightness_tolerance: 0,
          temperature_mired_tolerance: 0
        )

      if keys == [] do
        []
      else
        [%{light_id: light_id, expected: expected, actual: actual, diverging_keys: keys}]
      end
    end)
  end

  defp convergence_divergences(light_ids, keys) do
    Enum.flat_map(light_ids, fn light_id ->
      desired = DesiredState.get(:light, light_id) |> Kernel.||(%{}) |> select_keys(keys)
      physical = State.get(:light, light_id) |> Kernel.||(%{}) |> select_keys(keys)

      keys =
        LightStateSemantics.diverging_keys(desired, physical,
          brightness_tolerance: @brightness_tolerance,
          temperature_mired_tolerance: @temperature_mired_tolerance
        )

      if keys == [] do
        []
      else
        [%{light_id: light_id, expected: desired, actual: physical, diverging_keys: keys}]
      end
    end)
  end

  defp off_desired_states(light_ids) do
    Map.new(light_ids, fn light_id -> {light_id, %{power: :off}} end)
  end

  defp subset_desired_states(baseline, light_ids) do
    Map.take(baseline, light_ids)
  end

  defp capture_desired_states(light_ids) do
    Map.new(light_ids, fn light_id -> {light_id, DesiredState.get(:light, light_id) || %{}} end)
  end

  defp select_keys(state, nil) when is_map(state), do: state

  defp select_keys(state, keys) when is_map(state) and is_list(keys) do
    Map.take(state, keys)
  end

  defp select_keys(state, _keys), do: state

  defp expand_control_group_light_ids(room_id, %{
         "group_ids" => group_ids,
         "light_ids" => light_ids
       }) do
    allowed_light_ids =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id and is_nil(l.canonical_light_id),
          select: l.id
        )
      )
      |> MapSet.new()

    group_light_ids =
      group_ids
      |> normalize_integer_ids()
      |> Enum.flat_map(&Groups.member_light_ids/1)

    direct_light_ids =
      light_ids
      |> normalize_integer_ids()
      |> Enum.filter(&MapSet.member?(allowed_light_ids, &1))

    (group_light_ids ++ direct_light_ids)
    |> Enum.filter(&MapSet.member?(allowed_light_ids, &1))
    |> Enum.uniq()
  end

  defp expand_control_group_light_ids(_room_id, _group), do: []

  defp find_single_control_group_button!(device, action_type, group_id) do
    Enum.find(device.buttons, fn button ->
      config = Hueworks.Schemas.PicoButton.action_config_struct(button)

      button.enabled and button.action_type == action_type and
        config.target_kind == :control_groups and
        config.target_ids == [group_id]
    end) || raise "missing #{action_type} button for control group #{inspect(group_id)}"
  end

  defp find_all_control_groups_button!(device, action_type) do
    all_group_ids =
      device
      |> Picos.control_groups()
      |> Enum.map(& &1["id"])
      |> Enum.sort()

    Enum.find(device.buttons, fn button ->
      config = Hueworks.Schemas.PicoButton.action_config_struct(button)

      button.enabled and button.action_type == action_type and
        config.target_kind == :control_groups and
        Enum.sort(config.target_ids) == all_group_ids
    end) || raise "missing #{action_type} button for all control groups"
  end

  defp load_lights_by_id(light_ids) do
    Repo.all(from(l in Light, where: l.id in ^light_ids))
    |> Map.new(&{&1.id, &1})
  end

  defp normalize_integer_ids(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_integer(value) ->
        [value]

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> [parsed]
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp smoke_trace(label) do
    %{
      trace_id: "hardware-smoke-#{label}-#{System.unique_integer([:positive])}",
      source: "hardware_smoke.#{label}",
      started_at_ms: System.monotonic_time(:millisecond)
    }
  end

  defp print_scenario_summary(scenario, loops, timeout_ms, poll_ms, settle_ms) do
    info("Running hardware smoke scenario: kitchen_accent_pico")
    info("  Room: #{scenario.room.name} (#{scenario.room.id})")
    info("  Scene: #{scenario.scene.name} (#{scenario.scene.id})")
    info("  Pico: #{scenario.device.name} (#{scenario.device.id})")
    info("  Loops: #{loops}")
    info("  Timeout: #{timeout_ms}ms")
    info("  Poll: #{poll_ms}ms")
    info("  Settle: #{settle_ms}ms")

    info(
      "  Overhead lights: #{format_light_list(scenario.groups.overhead.light_ids, scenario.lights)}"
    )

    info("  Lower lights: #{format_light_list(scenario.groups.lower.light_ids, scenario.lights)}")
    info("  All lights: #{format_light_list(scenario.all_light_ids, scenario.lights)}")
  end

  defp print_lower_repeat_summary(scenario, cycles, timeout_ms, poll_ms, settle_ms) do
    info("Running hardware smoke scenario: kitchen_accent_lower_repeat")
    info("  Room: #{scenario.room.name} (#{scenario.room.id})")
    info("  Scene: #{scenario.scene.name} (#{scenario.scene.id})")
    info("  Pico: #{scenario.device.name} (#{scenario.device.id})")
    info("  Cycles: #{cycles}")
    info("  Timeout: #{timeout_ms}ms")
    info("  Poll: #{poll_ms}ms")
    info("  Settle: #{settle_ms}ms")
    info("  Lower lights: #{format_light_list(scenario.groups.lower.light_ids, scenario.lights)}")
  end

  defp sleep_settle(ms) when is_integer(ms) and ms > 0, do: Process.sleep(ms)
  defp sleep_settle(_ms), do: :ok

  defp format_light_list(light_ids, lights_by_id) do
    light_ids
    |> Enum.map(fn light_id ->
      case Map.get(lights_by_id, light_id) do
        nil -> "#{light_id}"
        light -> "#{light.name}##{light.id}/#{light.source}@bridge#{light.bridge_id}"
      end
    end)
    |> Enum.join(", ")
  end

  defp format_divergences(divergences, lights_by_id) do
    divergences
    |> Enum.map(fn divergence ->
      light = Map.get(lights_by_id, divergence.light_id)

      light_label =
        if light, do: "#{light.name}##{light.id}", else: "light##{divergence.light_id}"

      "- #{light_label} diverging_keys=#{inspect(divergence.diverging_keys)} expected=#{inspect(divergence.expected)} actual=#{inspect(divergence.actual)}"
    end)
    |> Enum.join("\n")
  end

  defp info(message), do: Logger.info(message)
end
