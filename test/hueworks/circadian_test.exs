defmodule Hueworks.CircadianTest do
  use ExUnit.Case, async: true

  alias Hueworks.Circadian

  @solar_config %{latitude: 40.7128, longitude: -74.0060, timezone: "Etc/UTC"}

  test "default mode matches the expected day, sunset, and midnight values" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "min_brightness" => 1,
      "max_brightness" => 100,
      "min_color_temp" => 2000,
      "max_color_temp" => 5500
    }

    assert {:ok, noon} = Circadian.calculate(config, @solar_config, utc_dt("2026-03-08T12:00:00Z"))
    assert noon.brightness == 100
    assert noon.kelvin == 5500
    assert_in_delta noon.sun_position, 1.0, 1.0e-6

    assert {:ok, sunset} =
             Circadian.calculate(config, @solar_config, utc_dt("2026-03-08T18:00:00Z"))

    assert sunset.brightness == 100
    assert sunset.kelvin == 2000
    assert_in_delta sunset.sun_position, 0.0, 1.0e-6

    assert {:ok, midnight} =
             Circadian.calculate(config, @solar_config, utc_dt("2026-03-09T00:00:00Z"))

    assert midnight.brightness == 1
    assert midnight.kelvin == 2000
    assert_in_delta midnight.sun_position, -1.0, 1.0e-6
  end

  test "linear brightness mode follows the HA sunrise ramp" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "min_brightness" => 10,
      "max_brightness" => 90,
      "brightness_mode" => "linear",
      "brightness_mode_time_dark" => 900,
      "brightness_mode_time_light" => 3600
    }

    assert {:ok, before_sunrise} =
             Circadian.calculate(config, @solar_config, utc_dt("2026-03-08T05:45:00Z"))

    assert before_sunrise.brightness == 10

    assert {:ok, midpoint} =
             Circadian.calculate(config, @solar_config, utc_dt("2026-03-08T06:22:30Z"))

    assert midpoint.brightness == 50

    assert {:ok, after_ramp} =
             Circadian.calculate(config, @solar_config, utc_dt("2026-03-08T07:00:00Z"))

    assert after_ramp.brightness == 90
  end

  test "tanh brightness mode matches the HA scaled tanh curve" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "min_brightness" => 10,
      "max_brightness" => 90,
      "brightness_mode" => "tanh",
      "brightness_mode_time_dark" => 900,
      "brightness_mode_time_light" => 3600
    }

    now = utc_dt("2026-03-08T06:10:00Z")

    assert {:ok, result} = Circadian.calculate(config, @solar_config, now)

    expected =
      scaled_tanh(600,
        x1: -900,
        x2: 3600,
        y1: 0.05,
        y2: 0.95,
        y_min: 10,
        y_max: 90
      )
      |> clamp(10, 90)
      |> round()

    assert result.brightness == expected
  end

  test "astronomical sunrise and sunset path works with lat/lon/timezone only" do
    config = %{
      "min_brightness" => 5,
      "max_brightness" => 85,
      "min_color_temp" => 2200,
      "max_color_temp" => 5000
    }

    assert {:ok, result} =
             Circadian.calculate(config, @solar_config, utc_dt("2026-03-08T12:00:00Z"))

    assert result.brightness in 5..85
    assert result.kelvin in 2200..5000
    assert result.sun_position >= -1.0
    assert result.sun_position <= 1.0
  end

  defp utc_dt(iso8601) do
    {:ok, datetime, 0} = DateTime.from_iso8601(iso8601)
    datetime
  end

  defp scaled_tanh(x, opts) do
    x1 = Keyword.fetch!(opts, :x1)
    x2 = Keyword.fetch!(opts, :x2)
    y1 = Keyword.fetch!(opts, :y1)
    y2 = Keyword.fetch!(opts, :y2)
    y_min = Keyword.fetch!(opts, :y_min)
    y_max = Keyword.fetch!(opts, :y_max)
    {a, b} = find_a_b(x1, x2, y1, y2)
    y_min + (y_max - y_min) * 0.5 * (:math.tanh(a * (x - b)) + 1)
  end

  defp find_a_b(x1, x2, y1, y2) do
    a = (:math.atanh(2 * y2 - 1) - :math.atanh(2 * y1 - 1)) / (x2 - x1)
    b = x1 - :math.atanh(2 * y1 - 1) / a
    {a, b}
  end

  defp clamp(value, minimum, maximum), do: max(minimum, min(value, maximum))
end
