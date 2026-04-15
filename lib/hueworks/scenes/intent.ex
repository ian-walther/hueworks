defmodule Hueworks.Scenes.Intent do
  @moduledoc false

  require Logger

  alias Hueworks.AppSettings
  alias Hueworks.Color
  alias Hueworks.Circadian
  alias Hueworks.Control.DesiredState
  alias Hueworks.Schemas.{LightState, Scene}

  def build_transaction(%Scene{} = scene, opts \\ []) do
    occupied = Keyword.get(opts, :occupied, false)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    target_light_ids = opts |> Keyword.get(:target_light_ids, []) |> MapSet.new()
    circadian_only = Keyword.get(opts, :circadian_only, false)
    power_overrides = Keyword.get(opts, :power_overrides, %{})
    preserve_power_latches = Keyword.get(opts, :preserve_power_latches, true)

    txn = DesiredState.begin(scene.id)

    Enum.reduce(scene.scene_components, txn, fn component, acc ->
      if skip_component?(component, circadian_only) do
        acc
      else
        desired = desired_from_light_state(component.light_state, now)
        default_power_by_light = component_default_power_map(component)
        component_lights = target_component_lights(component.lights, target_light_ids)

        Enum.reduce(component_lights, acc, fn light, txn ->
          current_desired = DesiredState.get(:light, light.id) || %{}
          power_override = Map.get(power_overrides, light.id)

          light_desired =
            desired
            |> maybe_apply_default_power(
              component.light_state,
              Map.get(default_power_by_light, light.id, :force_on),
              occupied
            )
            |> maybe_preserve_manual_power_latch(
              current_desired,
              preserve_power_latches and is_nil(power_override)
            )
            |> maybe_apply_power_override(power_override)

          DesiredState.apply(txn, :light, light.id, light_desired)
        end)
      end
    end)
  end

  def default_power_for_light(component, light_id) do
    defaults =
      Map.get(component, :light_defaults) ||
        Map.get(component, "light_defaults") ||
        %{}

    defaults
    |> light_default_lookup(light_id)
    |> parse_default_power()
  end

  defp desired_from_light_state(%LightState{type: :manual, config: config}, _now) do
    config = LightState.manual_config(config)
    base = %{power: :on}
    mode = Map.get(config, :mode, :temperature)

    base
    |> maybe_put(:brightness, config)
    |> maybe_put_manual_color(mode, config)
    |> maybe_put_manual_temperature(mode, config)
  end

  defp desired_from_light_state(%LightState{type: :circadian, config: config}, now) do
    solar_config = AppSettings.global_map()
    base = %{power: :on}

    case Circadian.calculate(config || %{}, solar_config, now) do
      {:ok, circadian} ->
        base
        |> Map.put(:brightness, circadian.brightness)
        |> Map.put(:kelvin, circadian.kelvin)

      {:error, reason} ->
        Logger.warning("Skipping circadian apply due to calculation error: #{inspect(reason)}")
        %{}
    end
  end

  defp desired_from_light_state(_, _now), do: %{}

  defp maybe_put_manual_temperature(attrs, :temperature, config) do
    maybe_put(attrs, :kelvin, config)
  end

  defp maybe_put_manual_temperature(attrs, _mode, _config), do: attrs

  defp maybe_put_manual_color(attrs, :color, config) do
    hue = Map.get(config, :hue)
    saturation = Map.get(config, :saturation)

    case Color.hs_to_xy(hue, saturation) do
      {x, y} ->
        attrs
        |> Map.put(:x, x)
        |> Map.put(:y, y)

      _ ->
        attrs
    end
  end

  defp maybe_put_manual_color(attrs, _mode, _config), do: attrs

  defp maybe_apply_default_power(desired, %LightState{type: type}, power_policy, occupied)
       when type in [:manual, :circadian] do
    Map.put(desired, :power, resolve_power_policy(power_policy, occupied))
  end

  defp maybe_apply_default_power(desired, _light_state, _power_policy, _occupied), do: desired

  defp resolve_power_policy(:force_on, _occupied), do: :on
  defp resolve_power_policy("force_on", _occupied), do: :on
  defp resolve_power_policy(:force_off, _occupied), do: :off
  defp resolve_power_policy("force_off", _occupied), do: :off
  defp resolve_power_policy(:follow_occupancy, true), do: :on
  defp resolve_power_policy("follow_occupancy", true), do: :on
  defp resolve_power_policy(:follow_occupancy, false), do: :off
  defp resolve_power_policy("follow_occupancy", false), do: :off
  defp resolve_power_policy(_unknown, _occupied), do: :on

  defp component_default_power_map(component) do
    component
    |> Map.get(:scene_component_lights, [])
    |> Enum.reduce(%{}, fn join, acc ->
      Map.put(acc, join.light_id, parse_default_power(join.default_power))
    end)
  end

  defp maybe_put(attrs, key, config) do
    value = Map.get(config, key)

    if is_nil(value) do
      attrs
    else
      Map.put(attrs, key, value)
    end
  end

  defp light_default_lookup(defaults, light_id) when is_map(defaults) do
    cond do
      Map.has_key?(defaults, light_id) ->
        Map.get(defaults, light_id)

      Map.has_key?(defaults, to_string(light_id)) ->
        Map.get(defaults, to_string(light_id))

      true ->
        nil
    end
  end

  defp light_default_lookup(_defaults, _light_id), do: nil

  defp parse_default_power(value) when value in [nil, true, "true", 1, "1", :on, "on"],
    do: :force_on

  defp parse_default_power(value) when value in [false, "false", 0, "0", :off, "off"],
    do: :force_off

  defp parse_default_power(value) when value in [:force_on, "force_on"], do: :force_on
  defp parse_default_power(value) when value in [:force_off, "force_off"], do: :force_off

  defp parse_default_power(value) when value in [:follow_occupancy, "follow_occupancy"],
    do: :follow_occupancy

  defp parse_default_power(_value), do: :force_on

  defp skip_component?(%{light_state: %LightState{type: :circadian}}, true), do: false
  defp skip_component?(%{light_state: %LightState{}}, true), do: true
  defp skip_component?(_component, false), do: false

  defp target_component_lights(lights, target_light_ids)
       when is_struct(target_light_ids, MapSet) do
    if MapSet.size(target_light_ids) == 0 do
      lights
    else
      Enum.filter(lights, &MapSet.member?(target_light_ids, &1.id))
    end
  end

  defp target_component_lights(lights, _target_light_ids), do: lights

  defp maybe_preserve_manual_power_latch(desired, current_desired, true) do
    cond do
      explicit_off_intent?(current_desired) and not explicit_off_intent?(desired) ->
        %{power: :off}

      explicit_on_intent?(current_desired) and explicit_off_intent?(desired) ->
        Map.put(desired, :power, :on)

      true ->
        desired
    end
  end

  defp maybe_preserve_manual_power_latch(desired, _current_desired, _preserve_power_latches),
    do: desired

  defp maybe_apply_power_override(desired, nil), do: desired

  defp maybe_apply_power_override(desired, power) when power in [:on, :off],
    do: Map.put(desired, :power, power)

  defp maybe_apply_power_override(desired, "on"), do: Map.put(desired, :power, :on)
  defp maybe_apply_power_override(desired, "off"), do: Map.put(desired, :power, :off)
  defp maybe_apply_power_override(desired, _power), do: desired

  defp explicit_off_intent?(state) when is_map(state) do
    Map.get(state, :power) == :off
  end

  defp explicit_off_intent?(_state), do: false

  defp explicit_on_intent?(state) when is_map(state) do
    Map.get(state, :power) == :on
  end

  defp explicit_on_intent?(_state), do: false
end
