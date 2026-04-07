defmodule Hueworks.Circadian do
  @moduledoc """
  Circadian brightness and kelvin calculation with near-parity to Home Assistant
  Adaptive Lighting's sunrise/sunset-based formulas.
  """

  require Logger

  alias Hueworks.Circadian.Config

  @sun_event_order [:sunrise, :noon, :sunset, :midnight]
  @allowed_orders Enum.map(0..3, fn index ->
                    Enum.drop(@sun_event_order, index) ++ Enum.take(@sun_event_order, index)
                  end)

  @type calc_result :: %{
          brightness: integer(),
          kelvin: integer(),
          sun_position: float()
        }

  @spec calculate(map(), map(), DateTime.t()) :: {:ok, calc_result()} | {:error, term()}
  def calculate(config, solar_config, now \\ DateTime.utc_now())

  def calculate(config, solar_config, now) when is_map(config) and is_map(solar_config) do
    with {:ok, normalized} <- normalize_config(config),
         {:ok, timezone} <- timezone_name(solar_config),
         {:ok, context} <- build_context(normalized, solar_config, timezone, now) do
      sun_position = sun_position(context, context.now_utc)

      {:ok,
       %{
         brightness: round(brightness_pct(context.config, context, context.now_utc)),
         kelvin: color_temp_kelvin(context.config, sun_position),
         sun_position: sun_position
       }}
    end
  end

  def calculate(_config, _solar_config, _now), do: {:error, :invalid_args}

  @spec day_events_for_date(map(), map(), Date.t()) ::
          {:ok, keyword(DateTime.t())} | {:error, term()}
  def day_events_for_date(config, solar_config, %Date{} = date)
      when is_map(config) and is_map(solar_config) do
    with {:ok, normalized} <- normalize_config(config),
         {:ok, timezone} <- timezone_name(solar_config),
         {:ok, sunrise} <- sunrise(normalized, solar_config, timezone, date),
         {:ok, sunset} <- sunset(normalized, solar_config, timezone, date),
         {:ok, noon, midnight} <-
           noon_and_midnight(normalized, solar_config, timezone, date, sunrise, sunset),
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

  def day_events_for_date(_config, _solar_config, _date), do: {:error, :invalid_args}

  defp normalize_config(config) do
    config
    |> stringify_keys()
    |> then(&Map.merge(Config.defaults(), &1))
    |> Config.normalize()
  end

  defp build_context(config, solar_config, timezone, now) do
    now_utc = ensure_utc(now)

    with {:ok, _local_now} <- DateTime.shift_zone(now_utc, timezone),
         {:ok, events} <- sun_events(config, solar_config, timezone, now_utc) do
      {:ok,
       %{
         config: config,
         events: events,
         now_utc: now_utc,
         solar_config: solar_config,
         timezone: timezone
       }}
    end
  end

  defp ensure_utc(%DateTime{} = now), do: DateTime.shift_zone!(now, "Etc/UTC")

  defp sun_events(config, solar_config, timezone, now_utc) do
    date = DateTime.to_date(now_utc)

    with {:ok, sunrise} <- sunrise(config, solar_config, timezone, date),
         {:ok, sunset} <- sunset(config, solar_config, timezone, date),
         {:ok, noon, midnight} <-
           noon_and_midnight(config, solar_config, timezone, date, sunrise, sunset),
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

  defp sunrise(config, solar_config, timezone, date) do
    base =
      case config["sunrise_time"] do
        nil -> solar_event(date, solar_config, :sunrise)
        time -> combine_local_time(date, time, timezone)
      end

    with {:ok, sunrise} <- base do
      sunrise
      |> DateTime.add(config["sunrise_offset"], :second)
      |> clamp_time(date, config["min_sunrise_time"], config["max_sunrise_time"], timezone)
      |> then(&{:ok, &1})
    end
  end

  defp sunset(config, solar_config, timezone, date) do
    base =
      case config["sunset_time"] do
        nil -> solar_event(date, solar_config, :sunset)
        time -> combine_local_time(date, time, timezone)
      end

    with {:ok, sunset} <- base do
      sunset
      |> DateTime.add(config["sunset_offset"], :second)
      |> clamp_time(date, config["min_sunset_time"], config["max_sunset_time"], timezone)
      |> then(&{:ok, &1})
    end
  end

  defp noon_and_midnight(config, solar_config, _timezone, date, sunrise, sunset) do
    if solar_times_constrained?(config) do
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
      with {:ok, noon} <- solar_event(date, solar_config, :noon) do
        midnight = DateTime.add(noon, midnight_offset_seconds(noon), :second)
        {:ok, noon, midnight}
      end
    end
  end

  defp solar_times_constrained?(config) do
    Enum.any?([
      config["sunrise_time"],
      config["sunset_time"],
      config["min_sunrise_time"],
      config["max_sunrise_time"],
      config["min_sunset_time"],
      config["max_sunset_time"]
    ])
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

  defp prev_and_next_events(context, now_utc) do
    all_events =
      for offset <- -1..1,
          event <- events_for_offset(context, now_utc, offset),
          do: event

    all_events = Enum.sort_by(all_events, fn {_name, dt} -> timestamp(dt) end)
    target = timestamp(now_utc)

    next_index =
      Enum.find_index(all_events, fn {_event, dt} ->
        timestamp(dt) > target
      end)

    next_index = next_index || max(length(all_events) - 1, 1)

    {
      Enum.at(all_events, next_index - 1),
      Enum.at(all_events, next_index)
    }
  end

  defp events_for_offset(context, now_utc, offset) do
    target = DateTime.add(now_utc, offset * 86_400, :second)

    case sun_events(context.config, context.solar_config, context.timezone, target) do
      {:ok, events} ->
        events

      {:error, reason} ->
        raise ArgumentError, "failed to calculate neighboring sun events: #{inspect(reason)}"
    end
  end

  defp sun_position(context, now_utc) do
    {{_prev_event, prev_dt}, {next_event, next_dt}} = prev_and_next_events(context, now_utc)
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

  defp brightness_pct(config, context, now_utc) do
    case config["brightness_mode"] do
      "default" ->
        sun_position = sun_position(context, now_utc)

        if sun_position > 0 do
          config["max_brightness"]
        else
          delta = config["max_brightness"] - config["min_brightness"]
          delta * (1 + sun_position) + config["min_brightness"]
        end

      mode when mode in ["linear", "tanh"] ->
        {event, event_dt} = closest_event(context, now_utc)
        delta_seconds = timestamp(now_utc) - timestamp(event_dt)
        dark = config["brightness_mode_time_dark"]
        light = config["brightness_mode_time_light"]

        brightness =
          case {mode, event} do
            {"linear", :sunrise} ->
              lerp(
                delta_seconds,
                -dark,
                light,
                config["min_brightness"],
                config["max_brightness"]
              )

            {"linear", :sunset} ->
              lerp(
                delta_seconds,
                -light,
                dark,
                config["max_brightness"],
                config["min_brightness"]
              )

            {"tanh", :sunrise} ->
              scaled_tanh(delta_seconds,
                x1: -dark,
                x2: light,
                y1: 0.05,
                y2: 0.95,
                y_min: config["min_brightness"],
                y_max: config["max_brightness"]
              )

            {"tanh", :sunset} ->
              scaled_tanh(delta_seconds,
                x1: -light,
                x2: dark,
                y1: 0.95,
                y2: 0.05,
                y_min: config["min_brightness"],
                y_max: config["max_brightness"]
              )
          end

        clamp(brightness, config["min_brightness"], config["max_brightness"])

      other ->
        Logger.warning("Unsupported circadian brightness mode: #{inspect(other)}")
        brightness_pct(Map.put(config, "brightness_mode", "default"), context, now_utc)
    end
  end

  defp closest_event(context, now_utc) do
    {prev, next} = prev_and_next_events(context, now_utc)

    cond do
      elem(prev, 0) == :sunrise or elem(next, 0) == :sunrise ->
        if elem(prev, 0) == :sunrise, do: prev, else: next

      elem(prev, 0) == :sunset or elem(next, 0) == :sunset ->
        if elem(prev, 0) == :sunset, do: prev, else: next

      true ->
        raise ArgumentError, "No sunrise or sunset event found"
    end
  end

  defp color_temp_kelvin(config, sun_position) when sun_position > 0 do
    delta = config["max_color_temp"] - config["min_color_temp"]
    round_to_5(delta * sun_position + config["min_color_temp"])
  end

  defp color_temp_kelvin(config, _sun_position), do: config["min_color_temp"]

  defp round_to_5(value), do: 5 * round(value / 5)

  defp solar_event(date, solar_config, :sunrise) do
    with {:ok, latitude, longitude} <- coordinates(solar_config),
         {:ok, naive} <- Solarex.Sun.rise(date, latitude, longitude) do
      {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
    end
  end

  defp solar_event(date, solar_config, :sunset) do
    with {:ok, latitude, longitude} <- coordinates(solar_config),
         {:ok, naive} <- Solarex.Sun.set(date, latitude, longitude) do
      {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
    end
  end

  defp solar_event(date, solar_config, :noon) do
    with {:ok, latitude, longitude} <- coordinates(solar_config) do
      {:ok, Solarex.Sun.noon(date, latitude, longitude)}
    end
  end

  defp coordinates(solar_config) do
    latitude =
      normalize_number(Map.get(solar_config, :latitude) || Map.get(solar_config, "latitude"))

    longitude =
      normalize_number(Map.get(solar_config, :longitude) || Map.get(solar_config, "longitude"))

    if is_number(latitude) and is_number(longitude) do
      {:ok, latitude * 1.0, longitude * 1.0}
    else
      {:error, :missing_coordinates}
    end
  end

  defp normalize_number(value) when is_integer(value), do: value * 1.0
  defp normalize_number(value) when is_float(value), do: value

  defp normalize_number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp normalize_number(_value), do: nil

  defp timezone_name(solar_config) do
    timezone =
      Map.get(solar_config, :timezone) ||
        Map.get(solar_config, "timezone") ||
        "Etc/UTC"

    if is_binary(timezone) and String.trim(timezone) != "" do
      {:ok, timezone}
    else
      {:ok, "Etc/UTC"}
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

  defp clamp_time(datetime, _date, nil, nil, _timezone), do: datetime

  defp clamp_time(datetime, date, min_time, max_time, timezone) do
    datetime =
      case min_time do
        nil -> datetime
        value -> max_datetime(datetime, combine_local_time!(date, value, timezone))
      end

    case max_time do
      nil -> datetime
      value -> min_datetime(datetime, combine_local_time!(date, value, timezone))
    end
  end

  defp combine_local_time!(date, time_string, timezone) do
    case combine_local_time(date, time_string, timezone) do
      {:ok, datetime} ->
        datetime

      {:error, reason} ->
        raise ArgumentError, "invalid circadian time #{inspect(time_string)}: #{inspect(reason)}"
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
  defp clamp(value, minimum, maximum), do: max(minimum, min(value, maximum))

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn {key, value} ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      {normalized_key, value}
    end)
  end
end
