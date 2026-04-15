defmodule Hueworks.CircadianPreview do
  @moduledoc """
  Builds day-preview samples for circadian light-state editing.
  """

  alias Hueworks.Circadian
  alias Hueworks.Circadian.Config
  alias __MODULE__.{Marker, Point, Result}

  @default_interval_minutes 10

  defmodule Point do
    @enforce_keys [:minute, :brightness, :kelvin]
    defstruct [:minute, :brightness, :kelvin]
  end

  defmodule Marker do
    @enforce_keys [:key, :label, :minute, :time_label]
    defstruct [:key, :label, :minute, :time_label]
  end

  defmodule Result do
    @enforce_keys [
      :date,
      :timezone,
      :config,
      :interval_minutes,
      :points,
      :markers,
      :brightness_markers,
      :temperature_markers,
      :min_brightness,
      :max_brightness,
      :min_kelvin,
      :max_kelvin
    ]
    defstruct [
      :date,
      :timezone,
      :config,
      :interval_minutes,
      :points,
      :markers,
      :brightness_markers,
      :temperature_markers,
      :min_brightness,
      :max_brightness,
      :min_kelvin,
      :max_kelvin
    ]
  end

  @type preview_point :: %Point{}
  @type preview_marker :: %Marker{}
  @type preview_result :: %Result{}

  @spec sample_day(map(), map(), Date.t() | String.t(), keyword()) ::
          {:ok, preview_result()} | {:error, term()}
  def sample_day(config, solar_config, date, opts \\ [])

  def sample_day(config, solar_config, date, opts) when is_map(config) and is_map(solar_config) do
    interval_minutes = Keyword.get(opts, :interval_minutes, @default_interval_minutes)

    with {:ok, normalized_config} <- normalize_config(config),
         {:ok, normalized_solar} <- normalize_solar_config(solar_config),
         {:ok, parsed_date} <- parse_date(date),
         {:ok, events} <-
           Circadian.day_events_for_date(normalized_config, normalized_solar, parsed_date),
         {:ok, brightness_events} <-
           Circadian.day_events_for_date(
             normalized_config,
             normalized_solar,
             parsed_date,
             curve: :brightness
           ),
         {:ok, temperature_events} <-
           Circadian.day_events_for_date(
             normalized_config,
             normalized_solar,
             parsed_date,
             curve: :temperature
           ),
         {:ok, points} <-
           sample_points(normalized_config, normalized_solar, parsed_date, interval_minutes) do
      {:ok,
       %Result{
         date: parsed_date,
         timezone: normalized_solar.timezone,
         config: normalized_config,
         interval_minutes: interval_minutes,
         points: points,
         markers: build_markers(events, parsed_date, normalized_solar.timezone),
         brightness_markers:
           build_markers(brightness_events, parsed_date, normalized_solar.timezone),
         temperature_markers:
           build_markers(temperature_events, parsed_date, normalized_solar.timezone),
         min_brightness: normalized_config[:min_brightness],
         max_brightness: normalized_config[:max_brightness],
         min_kelvin: normalized_config[:min_color_temp],
         max_kelvin: effective_max_kelvin(normalized_config)
       }}
    end
  end

  def sample_day(_config, _solar_config, _date, _opts), do: {:error, :invalid_args}

  defp normalize_config(config) do
    Config.runtime(config)
  end

  defp normalize_solar_config(solar_config) do
    latitude = parse_float(Map.get(solar_config, :latitude) || Map.get(solar_config, "latitude"))

    longitude =
      parse_float(Map.get(solar_config, :longitude) || Map.get(solar_config, "longitude"))

    timezone =
      parse_timezone(Map.get(solar_config, :timezone) || Map.get(solar_config, "timezone"))

    cond do
      is_nil(latitude) -> {:error, :missing_latitude}
      is_nil(longitude) -> {:error, :missing_longitude}
      is_nil(timezone) -> {:error, :missing_timezone}
      true -> {:ok, %{latitude: latitude, longitude: longitude, timezone: timezone}}
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  defp parse_date(_value), do: {:error, :invalid_date}

  defp sample_points(config, solar_config, date, interval_minutes) when interval_minutes > 0 do
    sample_minutes(interval_minutes)
    |> Enum.reduce_while({:ok, []}, fn minute, {:ok, acc} ->
      with {:ok, now_utc} <- local_minute_to_utc(date, minute, solar_config.timezone),
           {:ok, result} <- Circadian.calculate(config, solar_config, now_utc) do
        point = %Point{minute: minute, brightness: result.brightness, kelvin: result.kelvin}
        {:cont, {:ok, [point | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, points} -> {:ok, Enum.reverse(points)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sample_points(_config, _solar_config, _date, _interval_minutes),
    do: {:error, :invalid_interval}

  defp sample_minutes(interval_minutes) do
    minutes = Enum.to_list(0..1439//interval_minutes)

    if List.last(minutes) == 1439 do
      minutes
    else
      minutes ++ [1439]
    end
  end

  defp local_minute_to_utc(date, minute, timezone) do
    hour = div(minute, 60)
    minute_in_hour = rem(minute, 60)
    naive = NaiveDateTime.new!(date, Time.new!(hour, minute_in_hour, 0))

    case DateTime.from_naive(naive, timezone) do
      {:ok, datetime} -> {:ok, DateTime.shift_zone!(datetime, "Etc/UTC")}
      {:ambiguous, first, _second} -> {:ok, DateTime.shift_zone!(first, "Etc/UTC")}
      {:gap, _before, gap_after} -> {:ok, DateTime.shift_zone!(gap_after, "Etc/UTC")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_markers(events, date, timezone) do
    events
    |> Enum.filter(fn {key, _dt} -> key in [:sunrise, :noon, :sunset] end)
    |> Enum.reduce([], fn {key, datetime}, acc ->
      local = DateTime.shift_zone!(datetime, timezone)
      marker_date = DateTime.to_date(local)

      if marker_date == date do
        [
          %Marker{
            key: key,
            label: marker_label(key),
            minute: minute_of_day(local),
            time_label: format_time(local)
          }
          | acc
        ]
      else
        acc
      end
    end)
    |> Enum.reverse()
    |> Enum.sort_by(& &1.minute)
  end

  defp marker_label(:sunrise), do: "Sunrise"
  defp marker_label(:noon), do: "Noon"
  defp marker_label(:sunset), do: "Sunset"

  defp minute_of_day(%DateTime{hour: hour, minute: minute, second: second}) do
    hour * 60 + minute + second / 60
  end

  defp format_time(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_time()
    |> Time.to_iso8601()
    |> String.slice(0, 5)
  end

  defp parse_float(value) when is_integer(value), do: value * 1.0
  defp parse_float(value) when is_float(value), do: value

  defp parse_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp parse_float(_value), do: nil

  defp parse_timezone(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_timezone(_value), do: nil

  defp effective_max_kelvin(config) do
    config[:temperature_ceiling_kelvin] || config[:max_color_temp]
  end
end
