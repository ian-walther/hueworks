defmodule Hueworks.Circadian.Timing do
  @moduledoc """
  Effective sunrise and sunset timing for one circadian profile.

  Each event resolves independently. An inherited event is the astronomical
  event clamped by the global window, with no fixed time or offsets and the
  default ramp durations. An overridden event uses only the profile's stored
  timing and window. Values stored for an inherited event stay in the profile
  and have no effect here.
  """

  alias Hueworks.Circadian.Config

  defmodule Event do
    @moduledoc false

    @enforce_keys [
      :override?,
      :time,
      :offset,
      :min,
      :max,
      :brightness_offset,
      :temperature_offset,
      :dark_seconds,
      :light_seconds
    ]
    defstruct @enforce_keys
  end

  @enforce_keys [:sunrise, :sunset]
  defstruct @enforce_keys

  @type t :: %__MODULE__{sunrise: %Event{}, sunset: %Event{}}

  @window_fields [:min_sunrise_time, :max_sunrise_time, :min_sunset_time, :max_sunset_time]
  @ramp_fields ["brightness_mode_time_dark", "brightness_mode_time_light"]

  def window_fields, do: @window_fields

  @doc """
  Form keys whose stored values only apply while `event` is overridden.
  """
  def event_fields(event) when event in [:sunrise, :sunset] do
    event
    |> event_keys()
    |> Map.drop([:override])
    |> Map.values()
    |> Enum.map(&Atom.to_string/1)
  end

  @doc """
  Form keys for the shared ramp durations, which apply around overridden events.
  """
  def ramp_fields, do: @ramp_fields

  def override_field(event) when event in [:sunrise, :sunset] do
    event
    |> event_keys()
    |> Map.fetch!(:override)
    |> Atom.to_string()
  end

  def default_ramp do
    defaults = Config.defaults()

    %{
      dark_seconds: Map.fetch!(defaults, "brightness_mode_time_dark"),
      light_seconds: Map.fetch!(defaults, "brightness_mode_time_light")
    }
  end

  @doc """
  The effective values of an inherited event, keyed like stored profile config.
  """
  def inherited_values(event, global_window) when event in [:sunrise, :sunset] do
    keys = event_keys(event)
    inherited = inherited_event(keys, global_window)

    %{
      Atom.to_string(keys.time) => inherited.time,
      Atom.to_string(keys.offset) => inherited.offset,
      Atom.to_string(keys.min) => inherited.min,
      Atom.to_string(keys.max) => inherited.max,
      Atom.to_string(keys.brightness_offset) => inherited.brightness_offset,
      Atom.to_string(keys.temperature_offset) => inherited.temperature_offset
    }
  end

  def global_bounds(event, global_window) when event in [:sunrise, :sunset] do
    keys = event_keys(event)
    {global_window[keys.min], global_window[keys.max]}
  end

  @doc """
  Reads the global window from a solar config. Blank values mean unconstrained.
  """
  def global_window(solar_config) when is_map(solar_config) do
    with {:ok, window} <- parse_window(solar_config),
         :ok <- validate_window_order(window, :min_sunrise_time, :max_sunrise_time),
         :ok <- validate_window_order(window, :min_sunset_time, :max_sunset_time) do
      {:ok, window}
    end
  end

  @doc """
  Resolves runtime profile config and a global window into per-event timing.
  A missing override flag keeps a legacy profile's local behavior.
  """
  def resolve(config, global_window) when is_map(config) and is_map(global_window) do
    %__MODULE__{
      sunrise: resolve_event(:sunrise, config, global_window),
      sunset: resolve_event(:sunset, config, global_window)
    }
  end

  @doc """
  True when any effective fixed time or bound replaces the solar noon anchor.
  Inheritance alone does not constrain timing, and neither do ignored values.
  """
  def constrained?(%__MODULE__{sunrise: sunrise, sunset: sunset}) do
    Enum.any?([sunrise.time, sunrise.min, sunrise.max, sunset.time, sunset.min, sunset.max])
  end

  defp resolve_event(event, config, global_window) do
    keys = event_keys(event)

    if config[keys.override] == false do
      inherited_event(keys, global_window)
    else
      overridden_event(keys, config)
    end
  end

  defp inherited_event(keys, global_window) do
    ramp = default_ramp()

    %Event{
      override?: false,
      time: nil,
      offset: 0,
      min: global_window[keys.min],
      max: global_window[keys.max],
      brightness_offset: 0,
      temperature_offset: 0,
      dark_seconds: ramp.dark_seconds,
      light_seconds: ramp.light_seconds
    }
  end

  defp overridden_event(keys, config) do
    %Event{
      override?: true,
      time: config[keys.time],
      offset: config[keys.offset],
      min: config[keys.min],
      max: config[keys.max],
      brightness_offset: config[keys.brightness_offset],
      temperature_offset: config[keys.temperature_offset],
      dark_seconds: config[:brightness_mode_time_dark],
      light_seconds: config[:brightness_mode_time_light]
    }
  end

  defp parse_window(solar_config) do
    Enum.reduce_while(@window_fields, {:ok, %{}}, fn field, {:ok, window} ->
      value = Map.get(solar_config, field) || Map.get(solar_config, Atom.to_string(field))

      case Config.normalize_wall_clock_time(value) do
        {:ok, time} -> {:cont, {:ok, Map.put(window, field, time)}}
        {:error, _message} -> {:halt, {:error, {:invalid_global_window, field}}}
      end
    end)
  end

  defp validate_window_order(window, min_field, max_field) do
    min = window[min_field]
    max = window[max_field]

    if min && max && Time.compare(Time.from_iso8601!(min), Time.from_iso8601!(max)) == :gt do
      {:error, {:invalid_global_window, min_field}}
    else
      :ok
    end
  end

  defp event_keys(:sunrise) do
    %{
      override: :override_sunrise_timing,
      time: :sunrise_time,
      offset: :sunrise_offset,
      min: :min_sunrise_time,
      max: :max_sunrise_time,
      brightness_offset: :brightness_sunrise_offset,
      temperature_offset: :temperature_sunrise_offset
    }
  end

  defp event_keys(:sunset) do
    %{
      override: :override_sunset_timing,
      time: :sunset_time,
      offset: :sunset_offset,
      min: :min_sunset_time,
      max: :max_sunset_time,
      brightness_offset: :brightness_sunset_offset,
      temperature_offset: :temperature_sunset_offset
    }
  end
end
