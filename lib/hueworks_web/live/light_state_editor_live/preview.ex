defmodule HueworksWeb.LightStateEditorLive.Preview do
  @moduledoc false

  alias Hueworks.CircadianPreview

  @preview_interval_minutes 5
  @chart_width 640
  @chart_height 188
  @chart_padding %{left: 42, right: 14, top: 16, bottom: 28}

  def refresh_assigns(
        type,
        config,
        preview_date,
        preview_latitude,
        preview_longitude,
        preview_timezone
      )

  def refresh_assigns(
        :circadian,
        config,
        preview_date,
        preview_latitude,
        preview_longitude,
        preview_timezone
      ) do
    solar_config = %{
      latitude: preview_latitude,
      longitude: preview_longitude,
      timezone: preview_timezone
    }

    case CircadianPreview.sample_day(
           config,
           solar_config,
           preview_date,
           interval_minutes: @preview_interval_minutes
         ) do
      {:ok, preview} ->
        %{circadian_preview: preview, circadian_preview_error: nil}

      {:error, reason} ->
        %{
          circadian_preview: nil,
          circadian_preview_error: error_message(reason)
        }
    end
  end

  def refresh_assigns(
        _type,
        _config,
        _preview_date,
        _preview_latitude,
        _preview_longitude,
        _preview_timezone
      ) do
    %{circadian_preview: nil, circadian_preview_error: nil}
  end

  def error_message(:missing_latitude), do: "Preview needs a latitude."
  def error_message(:missing_longitude), do: "Preview needs a longitude."
  def error_message(:missing_timezone), do: "Preview needs a timezone."
  def error_message(:invalid_date), do: "Preview date must be valid."
  def error_message(:invalid_interval), do: "Preview interval must be positive."
  def error_message(:missing_coordinates), do: "Preview needs both latitude and longitude."
  def error_message(reason), do: "Preview unavailable: #{inspect(reason)}"

  def chart_view_box, do: "0 0 #{@chart_width} #{@chart_height}"

  def chart_path(nil, _metric), do: ""

  def chart_path(preview, metric) do
    preview.points
    |> Enum.map(fn point ->
      value = Map.fetch!(point, metric)
      "#{x_position(point.minute)} #{y_position(value, chart_domain(preview, metric))}"
    end)
    |> case do
      [] -> ""
      [first | rest] -> "M #{first} " <> Enum.map_join(rest, " ", &"L #{&1}")
    end
  end

  def chart_points_json(nil, _metric), do: "[]"

  def chart_points_json(preview, metric) do
    preview.points
    |> Enum.map(fn point ->
      value = Map.fetch!(point, metric)

      %{
        minute: point.minute,
        time_label: minute_label(point.minute),
        value: value,
        value_label: chart_value_label(metric, value),
        x: x_position(point.minute),
        y: y_position(value, chart_domain(preview, metric))
      }
    end)
    |> Jason.encode!()
  end

  def marker_x_position(minute), do: x_position(minute)

  def x_ticks do
    [
      %{minute: 0, label: "00:00"},
      %{minute: 360, label: "06:00"},
      %{minute: 720, label: "12:00"},
      %{minute: 1080, label: "18:00"},
      %{minute: 1440, label: "24:00"}
    ]
  end

  def y_ticks(preview, :brightness) do
    domain = chart_domain(preview, :brightness)

    [0, 25, 50, 75, 100]
    |> Enum.filter(fn value -> value >= elem(domain, 0) and value <= elem(domain, 1) end)
    |> Enum.map(&%{value: &1, label: "#{&1}%"})
  end

  def y_ticks(preview, :kelvin) do
    {min_kelvin, max_kelvin} = chart_domain(preview, :kelvin)
    step = max(round((max_kelvin - min_kelvin) / 4 / 25) * 25, 25)

    Stream.iterate(min_kelvin, &(&1 + step))
    |> Enum.take_while(&(&1 < max_kelvin))
    |> Kernel.++([max_kelvin])
    |> Enum.uniq()
    |> Enum.map(&%{value: &1, label: "#{&1}K"})
  end

  def marker_summary(nil, _key), do: "..."

  def marker_summary(preview, key) do
    case Enum.find(preview.markers, &(&1.key == key)) do
      nil -> "..."
      marker -> marker.time_label
    end
  end

  def range_label(nil, _metric), do: "..."

  def range_label(preview, :brightness),
    do: "#{preview.min_brightness}% - #{preview.max_brightness}%"

  def range_label(preview, :kelvin), do: "#{preview.min_kelvin}K - #{preview.max_kelvin}K"

  def chart_domain(_preview, :brightness), do: {0, 100}
  def chart_domain(nil, :kelvin), do: {0, 100}

  def chart_domain(preview, :kelvin) do
    min_kelvin = preview.min_kelvin
    max_kelvin = preview.max_kelvin

    if min_kelvin == max_kelvin do
      {min_kelvin - 100, max_kelvin + 100}
    else
      {min_kelvin, max_kelvin}
    end
  end

  def plot_width, do: @chart_width - @chart_padding.left - @chart_padding.right
  def plot_height, do: @chart_height - @chart_padding.top - @chart_padding.bottom
  def chart_top_padding, do: @chart_padding.top
  def chart_left_padding, do: @chart_padding.left
  def chart_bottom_y, do: @chart_height - @chart_padding.bottom
  def chart_x_label_y, do: @chart_height - 8

  def minute_label(total_minutes) do
    hour = div(total_minutes, 60)
    minute = rem(total_minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> IO.iodata_to_binary()
  end

  def chart_value_label(:brightness, value), do: "#{value}%"
  def chart_value_label(:kelvin, value), do: "#{value}K"

  def x_position(minute) do
    @chart_padding.left + plot_width() * minute / 1440
  end

  def y_position(value, {min_value, max_value}) do
    ratio =
      cond do
        max_value == min_value -> 0.5
        true -> (value - min_value) / (max_value - min_value)
      end

    @chart_padding.top + plot_height() * (1 - ratio)
  end

  def time_input_value(nil), do: ""
  def time_input_value(""), do: ""

  def time_input_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      <<hour::binary-size(2), ?:, minute::binary-size(2), ?:, second::binary-size(2)>> ->
        "#{hour}:#{minute}:#{second}"

      <<hour::binary-size(2), ?:, minute::binary-size(2)>> ->
        "#{hour}:#{minute}:00"

      other ->
        other
    end
  end

  def time_input_value(value) when is_integer(value), do: Integer.to_string(value)
  def time_input_value(value) when is_float(value), do: Float.to_string(value)
  def time_input_value(value), do: to_string(value)
end
