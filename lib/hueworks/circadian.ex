defmodule Hueworks.Circadian do
  @moduledoc """
  Circadian brightness and kelvin calculation with near-parity to Home Assistant
  Adaptive Lighting's sunrise/sunset-based formulas.
  """

  require Logger

  alias Hueworks.Circadian.Inputs
  alias Hueworks.Circadian.Timing
  alias Hueworks.Util

  @sun_event_order [:sunrise, :noon, :sunset, :midnight]
  @allowed_orders Enum.map(0..3, fn index ->
                    Enum.drop(@sun_event_order, index) ++ Enum.take(@sun_event_order, index)
                  end)
  @curves [:shared, :brightness, :temperature]

  @type calc_result :: %{
          brightness: integer(),
          kelvin: integer(),
          sun_position: float()
        }

  @doc """
  Normalizes a profile config and solar config once for repeated evaluation.
  """
  @spec prepare(map(), map()) :: {:ok, Inputs.t()} | {:error, term()}
  def prepare(config, solar_config), do: Inputs.load(config, solar_config)

  @spec calculate(map(), map(), DateTime.t()) :: {:ok, calc_result()} | {:error, term()}
  def calculate(config, solar_config, now \\ DateTime.utc_now())

  def calculate(config, solar_config, now) when is_map(config) and is_map(solar_config) do
    with {:ok, inputs} <- prepare(config, solar_config) do
      evaluate(inputs, now)
    end
  end

  def calculate(_config, _solar_config, _now), do: {:error, :invalid_args}

  @spec evaluate(Inputs.t(), DateTime.t()) :: {:ok, calc_result()} | {:error, term()}
  def evaluate(%Inputs{} = inputs, %DateTime{} = now) do
    now_utc = ensure_utc(now)

    with {:ok, local_now} <- DateTime.shift_zone(now_utc, inputs.timezone),
         {:ok, schedule} <- schedule(inputs, DateTime.to_date(local_now)),
         {:ok, brightness} <- brightness_pct(inputs, schedule.brightness, now_utc) do
      {:ok,
       %{
         brightness: round(brightness),
         kelvin: color_temp_kelvin(inputs.config, schedule.temperature, now_utc),
         sun_position: sun_position(schedule.shared, now_utc)
       }}
    end
  end

  @spec day_events_for_date(map(), map(), Date.t(), keyword()) ::
          {:ok, keyword(DateTime.t())} | {:error, term()}
  def day_events_for_date(config, solar_config, date, opts \\ [])

  def day_events_for_date(config, solar_config, %Date{} = date, opts)
      when is_map(config) and is_map(solar_config) and is_list(opts) do
    with {:ok, inputs} <- prepare(config, solar_config) do
      day_events(inputs, date, Keyword.get(opts, :curve, :shared))
    end
  end

  def day_events_for_date(_config, _solar_config, _date, _opts), do: {:error, :invalid_args}

  @doc """
  Effective events for a curve on a local calendar date.
  """
  @spec day_events(Inputs.t(), Date.t(), :shared | :brightness | :temperature) ::
          {:ok, keyword(DateTime.t())} | {:error, term()}
  def day_events(%Inputs{} = inputs, %Date{} = date, curve \\ :shared) do
    with {:ok, events} <- base_events(inputs, date) do
      apply_curve_offsets(events, inputs.timing, curve)
    end
  end

  @doc """
  True when the effective events cannot form a day on the local date. Failing to
  calculate an event is not an ordering problem, so it reports false.
  """
  @spec invalid_event_order?(map(), map(), Date.t()) :: boolean()
  def invalid_event_order?(config, solar_config, %Date{} = date) do
    with {:ok, inputs} <- prepare(config, solar_config),
         {:ok, _events} <- collect_ok(@curves, &day_events(inputs, date, &1)) do
      false
    else
      {:error, {:invalid_sun_event_order, _order}} -> true
      {:error, _reason} -> false
    end
  end

  @doc """
  The current calendar date in the solar config's timezone.
  """
  @spec local_today(map()) :: {:ok, Date.t()} | {:error, term()}
  def local_today(solar_config) when is_map(solar_config) do
    with {:ok, %Inputs{timezone: timezone}} <- prepare(%{}, solar_config),
         {:ok, local_now} <- DateTime.now(timezone) do
      {:ok, DateTime.to_date(local_now)}
    end
  end

  defp ensure_utc(%DateTime{} = now), do: DateTime.shift_zone!(now, "Etc/UTC")

  # Every curve's events for the local day and both neighbors, in time order.
  defp schedule(inputs, date) do
    with {:ok, days} <- collect_ok(-1..1, &base_events(inputs, Date.add(date, &1))),
         {:ok, curves} <- collect_ok(@curves, &curve_schedule(days, inputs.timing, &1)) do
      {:ok, @curves |> Enum.zip(curves) |> Map.new()}
    end
  end

  defp curve_schedule(days, timing, curve) do
    with {:ok, days} <- collect_ok(days, &apply_curve_offsets(&1, timing, curve)) do
      days
      |> List.flatten()
      |> Enum.sort_by(fn {_event, dt} -> timestamp(dt) end)
      |> then(&{:ok, &1})
    end
  end

  defp collect_ok(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, _reason} = error -> error
    end
  end

  defp base_events(inputs, date) do
    with {:ok, sunrise} <- sun_event(inputs, date, :sunrise),
         {:ok, sunset} <- sun_event(inputs, date, :sunset),
         {:ok, noon, midnight} <- noon_and_midnight(inputs, date, sunrise, sunset),
         :ok <-
           validate_sun_event_order(
             sunrise: sunrise,
             sunset: sunset,
             noon: noon,
             midnight: midnight
           ) do
      {:ok, [sunrise: sunrise, sunset: sunset, noon: noon, midnight: midnight]}
    end
  end

  defp apply_curve_offsets(events, _timing, :shared), do: {:ok, events}

  defp apply_curve_offsets(events, %Timing{} = timing, curve)
       when curve in [:brightness, :temperature] do
    events =
      events
      |> Keyword.update!(
        :sunrise,
        &DateTime.add(&1, curve_offset(timing.sunrise, curve), :second)
      )
      |> Keyword.update!(:sunset, &DateTime.add(&1, curve_offset(timing.sunset, curve), :second))

    case validate_sun_event_order(events) do
      :ok -> {:ok, events}
      {:error, _reason} = error -> error
    end
  end

  defp sun_event(inputs, date, name) do
    event = Map.fetch!(inputs.timing, name)

    base =
      case event.time do
        nil -> solar_event(inputs, date, name)
        time -> combine_local_time(date, time, inputs.timezone)
      end

    with {:ok, datetime} <- base do
      datetime
      |> DateTime.add(event.offset, :second)
      |> clamp_time(date, event.min, event.max, inputs.timezone)
    end
  end

  defp noon_and_midnight(inputs, date, sunrise, sunset) do
    if Timing.constrained?(inputs.timing) do
      middle_seconds = abs(DateTime.diff(sunset, sunrise, :second)) / 2

      if DateTime.compare(sunset, sunrise) == :gt do
        noon = DateTime.add(sunrise, round(middle_seconds), :second)
        midnight = DateTime.add(noon, midnight_offset_seconds(noon), :second)
        {:ok, noon, midnight}
      else
        midnight = DateTime.add(sunset, round(middle_seconds), :second)
        noon = DateTime.add(midnight, midnight_offset_seconds(midnight), :second)
        {:ok, noon, midnight}
      end
    else
      with {:ok, noon} <- solar_event(inputs, date, :noon) do
        midnight = DateTime.add(noon, midnight_offset_seconds(noon), :second)
        {:ok, noon, midnight}
      end
    end
  end

  defp midnight_offset_seconds(%DateTime{hour: hour}) when hour < 12, do: 12 * 3600
  defp midnight_offset_seconds(_datetime), do: -12 * 3600

  defp validate_sun_event_order(events) do
    order =
      events
      |> Enum.sort_by(fn {_event, dt} -> timestamp(dt) end)
      |> Enum.map(&elem(&1, 0))

    if order in @allowed_orders do
      :ok
    else
      {:error, {:invalid_sun_event_order, order}}
    end
  end

  defp prev_and_next_events(events, now_utc) do
    target = timestamp(now_utc)

    next_index =
      Enum.find_index(events, fn {_event, dt} ->
        timestamp(dt) > target
      end)

    next_index = next_index || max(length(events) - 1, 1)

    {
      Enum.at(events, next_index - 1),
      Enum.at(events, next_index)
    }
  end

  defp sun_position(events, now_utc) do
    {{_prev_event, prev_dt}, {next_event, next_dt}} = prev_and_next_events(events, now_utc)
    target_ts = timestamp(now_utc)
    prev_ts = timestamp(prev_dt)
    next_ts = timestamp(next_dt)

    {h, x} =
      if next_event in [:sunset, :sunrise] do
        {prev_ts, next_ts}
      else
        {next_ts, prev_ts}
      end

    k = if next_event in [:sunset, :noon], do: 1.0, else: -1.0
    k * (1 - :math.pow((target_ts - h) / (h - x), 2))
  end

  defp brightness_pct(%Inputs{config: config} = inputs, events, now_utc) do
    case config[:brightness_mode] do
      :quadratic ->
        sun_position = sun_position(events, now_utc)

        if sun_position > 0 do
          {:ok, config[:max_brightness]}
        else
          delta = config[:max_brightness] - config[:min_brightness]
          {:ok, delta * (1 + sun_position) + config[:min_brightness]}
        end

      mode when mode in [:linear, :tanh] ->
        with {:ok, {event, event_dt}} <- closest_event(events, now_utc) do
          ramped_brightness(
            mode,
            event,
            Map.fetch!(inputs.timing, event),
            timestamp(now_utc) - timestamp(event_dt),
            config
          )
        end

      other ->
        Logger.warning("Unsupported circadian brightness mode: #{inspect(other)}")

        inputs
        |> Map.put(:config, Map.put(config, :brightness_mode, :tanh))
        |> brightness_pct(events, now_utc)
    end
  end

  # A ramp with no width has no curve to evaluate.
  defp ramped_brightness(_mode, event, %{dark_seconds: 0, light_seconds: 0}, _delta, _config),
    do: {:error, {:zero_width_brightness_ramp, event}}

  defp ramped_brightness(mode, event, timing_event, delta_seconds, config) do
    dark = timing_event.dark_seconds
    light = timing_event.light_seconds

    brightness =
      case {mode, event} do
        {:linear, :sunrise} ->
          lerp(
            delta_seconds,
            -dark,
            light,
            config[:min_brightness],
            config[:max_brightness]
          )

        {:linear, :sunset} ->
          lerp(
            delta_seconds,
            -light,
            dark,
            config[:max_brightness],
            config[:min_brightness]
          )

        {:tanh, :sunrise} ->
          scaled_tanh(delta_seconds,
            x1: -dark,
            x2: light,
            y1: 0.05,
            y2: 0.95,
            y_min: config[:min_brightness],
            y_max: config[:max_brightness]
          )

        {:tanh, :sunset} ->
          scaled_tanh(delta_seconds,
            x1: -light,
            x2: dark,
            y1: 0.95,
            y2: 0.05,
            y_min: config[:min_brightness],
            y_max: config[:max_brightness]
          )
      end

    {:ok, Util.clamp(brightness, config[:min_brightness], config[:max_brightness])}
  end

  defp closest_event(events, now_utc) do
    {prev, next} = prev_and_next_events(events, now_utc)

    cond do
      elem(prev, 0) == :sunrise or elem(next, 0) == :sunrise ->
        {:ok, if(elem(prev, 0) == :sunrise, do: prev, else: next)}

      elem(prev, 0) == :sunset or elem(next, 0) == :sunset ->
        {:ok, if(elem(prev, 0) == :sunset, do: prev, else: next)}

      true ->
        {:error, :no_adjacent_sun_event}
    end
  end

  defp color_temp_kelvin(config, events, now_utc) do
    sun_position = sun_position(events, now_utc)

    kelvin =
      if sun_position > 0 do
        delta = config[:max_color_temp] - config[:min_color_temp]
        round_to_5(delta * sun_position + config[:min_color_temp])
      else
        config[:min_color_temp]
      end

    apply_temperature_ceiling(kelvin, config[:temperature_ceiling_kelvin])
  end

  defp apply_temperature_ceiling(kelvin, nil), do: kelvin

  defp apply_temperature_ceiling(kelvin, ceiling) when is_integer(ceiling),
    do: min(kelvin, ceiling)

  defp round_to_5(value), do: 5 * round(value / 5)

  defp solar_event(inputs, date, event) when event in [:sunrise, :sunset] do
    with {:ok, solar_noon} <- solar_noon(inputs, date) do
      solar_noon_ms = DateTime.to_unix(solar_noon, :millisecond)

      case Solarex.Sun.rise_hour_angle(solar_noon_ms, inputs.latitude * 1.0) do
        {:ok, rise_hour_angle} ->
          solar_noon_ms
          |> Kernel.+(sun_event_direction(event) * round(rise_hour_angle * 4 * 1000 * 60))
          |> DateTime.from_unix!(:millisecond)
          |> then(&{:ok, &1})

        {:error, _reason} ->
          {:error, {:sun_event_unavailable, event, date}}
      end
    end
  end

  defp solar_event(inputs, date, :noon), do: solar_noon(inputs, date)

  defp sun_event_direction(:sunrise), do: 1
  defp sun_event_direction(:sunset), do: -1

  # Solarex counts from a UTC calendar date, which can name the neighboring
  # local day near the date line. Select the solar noon of the local date.
  defp solar_noon(inputs, date) do
    with {:ok, latitude, longitude} <- coordinates(inputs),
         {:ok, local_noon} <- combine_local_time(date, "12:00:00", inputs.timezone) do
      date
      |> Date.add(-1)
      |> Date.range(Date.add(date, 1))
      |> Enum.map(&Solarex.Sun.noon(&1, latitude, longitude))
      |> Enum.min_by(&abs(DateTime.diff(&1, local_noon, :millisecond)))
      |> then(&{:ok, &1})
    end
  end

  defp coordinates(%Inputs{latitude: latitude, longitude: longitude}) do
    if is_number(latitude) and is_number(longitude) do
      {:ok, latitude * 1.0, longitude * 1.0}
    else
      {:error, :missing_coordinates}
    end
  end

  defp combine_local_time(date, time_string, timezone) do
    time = Time.from_iso8601!(time_string)
    naive = NaiveDateTime.new!(date, time)

    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} -> {:ok, DateTime.shift_zone!(datetime, "Etc/UTC")}
      {:ambiguous, first, _second} -> {:ok, DateTime.shift_zone!(first, "Etc/UTC")}
      {:gap, _before, gap_after} -> {:ok, DateTime.shift_zone!(gap_after, "Etc/UTC")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clamp_time(datetime, _date, nil, nil, _timezone), do: {:ok, datetime}

  defp clamp_time(datetime, date, min_time, max_time, timezone) do
    with {:ok, datetime} <- apply_bound(datetime, date, min_time, timezone, &max_datetime/2) do
      apply_bound(datetime, date, max_time, timezone, &min_datetime/2)
    end
  end

  defp apply_bound(datetime, _date, nil, _timezone, _select), do: {:ok, datetime}

  defp apply_bound(datetime, date, time, timezone, select) do
    with {:ok, bound} <- combine_local_time(date, time, timezone) do
      {:ok, select.(datetime, bound)}
    end
  end

  defp max_datetime(left, right) do
    if DateTime.compare(left, right) in [:gt, :eq], do: left, else: right
  end

  defp min_datetime(left, right) do
    if DateTime.compare(left, right) in [:lt, :eq], do: left, else: right
  end

  defp timestamp(%DateTime{} = datetime) do
    DateTime.to_unix(datetime, :microsecond) / 1_000_000
  end

  defp find_a_b(x1, x2, y1, y2) do
    a = (:math.atanh(2 * y2 - 1) - :math.atanh(2 * y1 - 1)) / (x2 - x1)
    b = x1 - :math.atanh(2 * y1 - 1) / a
    {a, b}
  end

  defp scaled_tanh(x, opts) do
    x1 = Keyword.fetch!(opts, :x1)
    x2 = Keyword.fetch!(opts, :x2)
    y1 = Keyword.get(opts, :y1, 0.05)
    y2 = Keyword.get(opts, :y2, 0.95)
    y_min = Keyword.get(opts, :y_min, 0.0)
    y_max = Keyword.get(opts, :y_max, 100.0)
    {a, b} = find_a_b(x1, x2, y1, y2)
    y_min + (y_max - y_min) * 0.5 * (:math.tanh(a * (x - b)) + 1)
  end

  defp lerp(x, x1, x2, y1, y2), do: y1 + (x - x1) * (y2 - y1) / (x2 - x1)
  defp curve_offset(event, :brightness), do: event.brightness_offset
  defp curve_offset(event, :temperature), do: event.temperature_offset
end
