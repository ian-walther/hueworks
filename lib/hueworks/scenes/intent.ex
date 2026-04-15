defmodule Hueworks.Scenes.Intent do
  @moduledoc false

  require Logger

  alias Hueworks.AppSettings
  alias Hueworks.Color
  alias Hueworks.Circadian
  alias Hueworks.Control.DesiredState
  alias Hueworks.Schemas.{LightState, Scene}

  defmodule BuildOptions do
    @moduledoc false

    @enforce_keys [
      :occupied,
      :now,
      :target_light_ids,
      :circadian_only,
      :power_overrides,
      :preserve_power_latches
    ]
    defstruct occupied: false,
              now: nil,
              target_light_ids: MapSet.new(),
              circadian_only: false,
              power_overrides: %{},
              preserve_power_latches: true

    def from_opts(opts) when is_list(opts) do
      target_light_ids =
        opts
        |> Keyword.get(:target_light_ids, [])
        |> normalize_target_light_ids()

      %__MODULE__{
        occupied: Keyword.get(opts, :occupied, false),
        now: Keyword.get(opts, :now, DateTime.utc_now()),
        target_light_ids: target_light_ids,
        circadian_only: Keyword.get(opts, :circadian_only, false),
        power_overrides: Keyword.get(opts, :power_overrides, %{}),
        preserve_power_latches: Keyword.get(opts, :preserve_power_latches, true)
      }
    end

    def from_opts(%__MODULE__{} = opts), do: opts

    defp normalize_target_light_ids(%MapSet{} = target_light_ids), do: target_light_ids

    defp normalize_target_light_ids(target_light_ids) when is_list(target_light_ids),
      do: MapSet.new(target_light_ids)

    defp normalize_target_light_ids(_target_light_ids), do: MapSet.new()
  end

  defmodule DesiredAttrs do
    @moduledoc false

    defstruct power: nil, brightness: nil, kelvin: nil, x: nil, y: nil

    def on, do: %__MODULE__{power: :on}

    def to_map(%__MODULE__{} = attrs) do
      attrs
      |> Map.from_struct()
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end
  end

  def build_transaction(%Scene{} = scene, opts \\ []) do
    %BuildOptions{
      occupied: occupied,
      now: now,
      target_light_ids: target_light_ids,
      circadian_only: circadian_only,
      power_overrides: power_overrides,
      preserve_power_latches: preserve_power_latches
    } = BuildOptions.from_opts(opts)

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

          DesiredState.apply(txn, :light, light.id, DesiredAttrs.to_map(light_desired))
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
    base = DesiredAttrs.on()
    mode = Map.get(config, :mode, :temperature)

    base
    |> maybe_put(:brightness, config)
    |> maybe_put_manual_color(mode, config)
    |> maybe_put_manual_temperature(mode, config)
  end

  defp desired_from_light_state(%LightState{type: :circadian, config: config}, now) do
    config = LightState.circadian_config(config)
    solar_config = AppSettings.global_map()
    base = DesiredAttrs.on()

    case Circadian.calculate(config, solar_config, now) do
      {:ok, circadian} ->
        base
        |> put_attr(:brightness, circadian.brightness)
        |> put_attr(:kelvin, circadian.kelvin)

      {:error, reason} ->
        Logger.warning("Skipping circadian apply due to calculation error: #{inspect(reason)}")
        %DesiredAttrs{}
    end
  end

  defp desired_from_light_state(_, _now), do: %DesiredAttrs{}

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
        |> put_attr(:x, x)
        |> put_attr(:y, y)

      _ ->
        attrs
    end
  end

  defp maybe_put_manual_color(attrs, _mode, _config), do: attrs

  defp maybe_apply_default_power(desired, %LightState{type: type}, power_policy, occupied)
       when type in [:manual, :circadian] do
    put_attr(desired, :power, resolve_power_policy(power_policy, occupied))
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
      put_attr(attrs, key, value)
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
        %DesiredAttrs{power: :off}

      explicit_on_intent?(current_desired) and explicit_off_intent?(desired) ->
        put_attr(desired, :power, :on)

      true ->
        desired
    end
  end

  defp maybe_preserve_manual_power_latch(desired, _current_desired, _preserve_power_latches),
    do: desired

  defp maybe_apply_power_override(desired, nil), do: desired

  defp maybe_apply_power_override(desired, power) when power in [:on, :off],
    do: put_attr(desired, :power, power)

  defp maybe_apply_power_override(desired, "on"), do: put_attr(desired, :power, :on)
  defp maybe_apply_power_override(desired, "off"), do: put_attr(desired, :power, :off)
  defp maybe_apply_power_override(desired, _power), do: desired

  defp explicit_off_intent?(state), do: power_value(state) == :off

  defp explicit_on_intent?(state), do: power_value(state) == :on

  defp put_attr(%DesiredAttrs{} = desired, key, value), do: Map.put(desired, key, value)
  defp put_attr(desired, key, value) when is_map(desired), do: Map.put(desired, key, value)

  defp power_value(%DesiredAttrs{power: power}), do: power
  defp power_value(state) when is_map(state), do: Map.get(state, :power)
  defp power_value(_state), do: nil
end
