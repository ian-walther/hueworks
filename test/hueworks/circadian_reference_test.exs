defmodule Hueworks.CircadianReferenceTest do
  use ExUnit.Case, async: true

  alias Hueworks.Circadian

  @solar_utc %{latitude: 40.7128, longitude: -74.0060, timezone: "Etc/UTC"}
  @solar_ny %{latitude: 40.7128, longitude: -74.0060, timezone: "America/New_York"}
  @solar_la %{latitude: 34.0522, longitude: -118.2437, timezone: "America/Los_Angeles"}

  test "quadratic mode keeps the current reference outputs across the full daily curve" do
    config =
      with_zero_curve_offsets(%{
        "brightness_mode" => "quadratic",
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 1,
        "max_brightness" => 100,
        "min_color_temp" => 2000,
        "max_color_temp" => 5500
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T00:00:00Z", 1, 2000, -1.0},
      {"2026-03-08T02:00:00Z", 12, 2000, -0.888889},
      {"2026-03-08T04:00:00Z", 45, 2000, -0.555556},
      {"2026-03-08T05:00:00Z", 70, 2000, -0.305556},
      {"2026-03-08T05:30:00Z", 84, 2000, -0.159722},
      {"2026-03-08T06:00:00Z", 100, 2000, 0.0},
      {"2026-03-08T06:30:00Z", 100, 2560, 0.159722},
      {"2026-03-08T08:00:00Z", 100, 3945, 0.555556},
      {"2026-03-08T10:00:00Z", 100, 5110, 0.888889},
      {"2026-03-08T12:00:00Z", 100, 5500, 1.0},
      {"2026-03-08T14:00:00Z", 100, 5110, 0.888889},
      {"2026-03-08T16:00:00Z", 100, 3945, 0.555556},
      {"2026-03-08T17:30:00Z", 100, 2560, 0.159722},
      {"2026-03-08T18:00:00Z", 100, 2000, 0.0},
      {"2026-03-08T18:30:00Z", 84, 2000, -0.159722},
      {"2026-03-08T20:00:00Z", 45, 2000, -0.555556},
      {"2026-03-08T22:00:00Z", 12, 2000, -0.888889}
    ])
  end

  test "linear mode keeps the current sunrise and sunset ramp shape" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 900,
        "brightness_mode_time_light" => 3600
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T05:45:00Z", 10, 2000, -0.081597},
      {"2026-03-08T05:50:00Z", 15, 2000, -0.054784},
      {"2026-03-08T05:55:00Z", 21, 2000, -0.027585},
      {"2026-03-08T06:00:00Z", 26, 2000, 0.0},
      {"2026-03-08T06:05:00Z", 31, 2085, 0.027585},
      {"2026-03-08T06:10:00Z", 37, 2165, 0.054784},
      {"2026-03-08T06:15:00Z", 42, 2245, 0.081597},
      {"2026-03-08T06:22:30Z", 50, 2365, 0.121094},
      {"2026-03-08T06:30:00Z", 58, 2480, 0.159722},
      {"2026-03-08T06:45:00Z", 74, 2705, 0.234375},
      {"2026-03-08T07:00:00Z", 90, 2915, 0.305556},
      {"2026-03-08T17:00:00Z", 90, 2915, 0.305556},
      {"2026-03-08T17:15:00Z", 74, 2705, 0.234375},
      {"2026-03-08T17:30:00Z", 58, 2480, 0.159722},
      {"2026-03-08T17:37:30Z", 50, 2365, 0.121094},
      {"2026-03-08T17:45:00Z", 42, 2245, 0.081597},
      {"2026-03-08T17:50:00Z", 37, 2165, 0.054784},
      {"2026-03-08T17:55:00Z", 31, 2085, 0.027585},
      {"2026-03-08T18:00:00Z", 26, 2000, 0.0},
      {"2026-03-08T18:05:00Z", 21, 2000, -0.027585},
      {"2026-03-08T18:10:00Z", 15, 2000, -0.054784},
      {"2026-03-08T18:15:00Z", 10, 2000, -0.081597}
    ])
  end

  test "linear mode keeps the current minute-level sunrise edge shape" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 900,
        "brightness_mode_time_light" => 3600
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T05:55:00Z", 21, 2000, -0.027585},
      {"2026-03-08T05:56:00Z", 22, 2000, -0.022099},
      {"2026-03-08T05:57:00Z", 23, 2000, -0.016597},
      {"2026-03-08T05:58:00Z", 24, 2000, -0.01108},
      {"2026-03-08T05:59:00Z", 25, 2000, -0.005548},
      {"2026-03-08T06:00:00Z", 26, 2000, 0.0},
      {"2026-03-08T06:01:00Z", 27, 2015, 0.005548},
      {"2026-03-08T06:02:00Z", 28, 2035, 0.01108},
      {"2026-03-08T06:03:00Z", 29, 2050, 0.016597},
      {"2026-03-08T06:04:00Z", 30, 2065, 0.022099},
      {"2026-03-08T06:05:00Z", 31, 2085, 0.027585}
    ])
  end

  test "linear mode keeps the current minute-level sunset edge shape" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 900,
        "brightness_mode_time_light" => 3600
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T17:55:00Z", 31, 2085, 0.027585},
      {"2026-03-08T17:56:00Z", 30, 2065, 0.022099},
      {"2026-03-08T17:57:00Z", 29, 2050, 0.016597},
      {"2026-03-08T17:58:00Z", 28, 2035, 0.01108},
      {"2026-03-08T17:59:00Z", 27, 2015, 0.005548},
      {"2026-03-08T18:00:00Z", 26, 2000, 0.0},
      {"2026-03-08T18:01:00Z", 25, 2000, -0.005548},
      {"2026-03-08T18:02:00Z", 24, 2000, -0.01108},
      {"2026-03-08T18:03:00Z", 23, 2000, -0.016597},
      {"2026-03-08T18:04:00Z", 22, 2000, -0.022099},
      {"2026-03-08T18:05:00Z", 21, 2000, -0.027585}
    ])
  end

  test "tanh mode keeps the current sunrise and sunset curve shape" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "tanh",
        "brightness_mode_time_dark" => 900,
        "brightness_mode_time_light" => 3600
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T05:45:00Z", 14, 2000, -0.081597},
      {"2026-03-08T05:50:00Z", 16, 2000, -0.054784},
      {"2026-03-08T05:55:00Z", 18, 2000, -0.027585},
      {"2026-03-08T06:00:00Z", 22, 2000, 0.0},
      {"2026-03-08T06:05:00Z", 26, 2085, 0.027585},
      {"2026-03-08T06:10:00Z", 32, 2165, 0.054784},
      {"2026-03-08T06:15:00Z", 39, 2245, 0.081597},
      {"2026-03-08T06:22:30Z", 50, 2365, 0.121094},
      {"2026-03-08T06:30:00Z", 61, 2480, 0.159722},
      {"2026-03-08T06:45:00Z", 78, 2705, 0.234375},
      {"2026-03-08T07:00:00Z", 86, 2915, 0.305556},
      {"2026-03-08T17:00:00Z", 86, 2915, 0.305556},
      {"2026-03-08T17:15:00Z", 78, 2705, 0.234375},
      {"2026-03-08T17:30:00Z", 61, 2480, 0.159722},
      {"2026-03-08T17:37:30Z", 50, 2365, 0.121094},
      {"2026-03-08T17:45:00Z", 39, 2245, 0.081597},
      {"2026-03-08T17:50:00Z", 32, 2165, 0.054784},
      {"2026-03-08T17:55:00Z", 26, 2085, 0.027585},
      {"2026-03-08T18:00:00Z", 22, 2000, 0.0},
      {"2026-03-08T18:05:00Z", 18, 2000, -0.027585},
      {"2026-03-08T18:10:00Z", 16, 2000, -0.054784},
      {"2026-03-08T18:15:00Z", 14, 2000, -0.081597}
    ])
  end

  test "tanh mode keeps the current minute-level sunrise edge shape" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "tanh",
        "brightness_mode_time_dark" => 900,
        "brightness_mode_time_light" => 3600
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T05:55:00Z", 18, 2000, -0.027585},
      {"2026-03-08T05:56:00Z", 19, 2000, -0.022099},
      {"2026-03-08T05:57:00Z", 20, 2000, -0.016597},
      {"2026-03-08T05:58:00Z", 20, 2000, -0.01108},
      {"2026-03-08T05:59:00Z", 21, 2000, -0.005548},
      {"2026-03-08T06:00:00Z", 22, 2000, 0.0},
      {"2026-03-08T06:01:00Z", 22, 2015, 0.005548},
      {"2026-03-08T06:02:00Z", 23, 2035, 0.01108},
      {"2026-03-08T06:03:00Z", 24, 2050, 0.016597},
      {"2026-03-08T06:04:00Z", 25, 2065, 0.022099},
      {"2026-03-08T06:05:00Z", 26, 2085, 0.027585}
    ])
  end

  test "tanh mode keeps the current minute-level sunset edge shape" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "tanh",
        "brightness_mode_time_dark" => 900,
        "brightness_mode_time_light" => 3600
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T17:55:00Z", 26, 2085, 0.027585},
      {"2026-03-08T17:56:00Z", 25, 2065, 0.022099},
      {"2026-03-08T17:57:00Z", 24, 2050, 0.016597},
      {"2026-03-08T17:58:00Z", 23, 2035, 0.01108},
      {"2026-03-08T17:59:00Z", 22, 2015, 0.005548},
      {"2026-03-08T18:00:00Z", 22, 2000, 0.0},
      {"2026-03-08T18:01:00Z", 21, 2000, -0.005548},
      {"2026-03-08T18:02:00Z", 20, 2000, -0.01108},
      {"2026-03-08T18:03:00Z", 20, 2000, -0.016597},
      {"2026-03-08T18:04:00Z", 19, 2000, -0.022099},
      {"2026-03-08T18:05:00Z", 18, 2000, -0.027585}
    ])
  end

  test "astronomical mode keeps the current New York spring reference outputs" do
    config =
      with_zero_curve_offsets(%{
        "brightness_mode" => "quadratic",
        "min_brightness" => 5,
        "max_brightness" => 85,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    assert_reference_outputs(config, @solar_ny, [
      {"2026-03-31T08:00:00Z", 27, 2200, -0.720293},
      {"2026-03-31T09:00:00Z", 45, 2200, -0.502903},
      {"2026-03-31T10:00:00Z", 67, 2200, -0.223435},
      {"2026-03-31T11:00:00Z", 85, 2480, 0.100397},
      {"2026-03-31T12:00:00Z", 85, 3250, 0.375356},
      {"2026-03-31T13:00:00Z", 85, 3880, 0.600305},
      {"2026-03-31T15:00:00Z", 85, 4720, 0.900173},
      {"2026-03-31T18:00:00Z", 85, 4930, 0.974898},
      {"2026-03-31T21:00:00Z", 85, 3880, 0.599534},
      {"2026-03-31T23:00:00Z", 85, 2480, 0.09924}
    ])
  end

  test "astronomical mode keeps the current Los Angeles winter reference outputs" do
    config =
      with_zero_curve_offsets(%{
        "brightness_mode" => "quadratic",
        "min_brightness" => 5,
        "max_brightness" => 85,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000
      })

    assert_reference_outputs(config, @solar_la, [
      {"2026-12-21T12:00:00Z", 33, 2200, -0.656165},
      {"2026-12-21T14:00:00Z", 66, 2200, -0.243664},
      {"2026-12-21T16:00:00Z", 85, 3290, 0.389412},
      {"2026-12-21T18:00:00Z", 85, 4605, 0.858192},
      {"2026-12-21T20:00:00Z", 85, 5000, 0.999202},
      {"2026-12-21T22:00:00Z", 85, 4475, 0.81244},
      {"2026-12-21T00:00:00Z", 85, 3025, 0.295168}
    ])
  end

  test "offset and clamp settings keep the current derived-solar outputs across the constrained curve" do
    config =
      with_zero_curve_offsets(%{
        "brightness_mode" => "quadratic",
        "min_brightness" => 5,
        "max_brightness" => 85,
        "min_color_temp" => 2200,
        "max_color_temp" => 5000,
        "sunrise_offset" => -1800,
        "min_sunrise_time" => "06:30:00",
        "max_sunrise_time" => "07:00:00",
        "sunset_offset" => 1800,
        "min_sunset_time" => "18:30:00",
        "max_sunset_time" => "19:00:00"
      })

    assert_reference_outputs(config, @solar_ny, [
      {"2026-03-31T10:00:00Z", 72, 2200, -0.166352},
      {"2026-03-31T10:30:00Z", 85, 2200, 0.0},
      {"2026-03-31T11:00:00Z", 85, 2630, 0.1536},
      {"2026-03-31T11:30:00Z", 85, 3025, 0.2944},
      {"2026-03-31T12:00:00Z", 85, 3385, 0.4224},
      {"2026-03-31T15:00:00Z", 85, 4780, 0.9216},
      {"2026-03-31T18:00:00Z", 85, 4890, 0.96},
      {"2026-03-31T22:00:00Z", 85, 3025, 0.2944},
      {"2026-03-31T23:00:00Z", 85, 2200, 0.0},
      {"2026-03-31T23:30:00Z", 72, 2200, -0.166352}
    ])
  end

  test "linear mode keeps the current asymmetric dark/light window behavior" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "linear",
        "brightness_mode_time_dark" => 1800,
        "brightness_mode_time_light" => 5400
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T05:30:00Z", 10, 2000, -0.159722},
      {"2026-03-08T05:45:00Z", 20, 2000, -0.081597},
      {"2026-03-08T06:00:00Z", 30, 2000, 0.0},
      {"2026-03-08T06:15:00Z", 40, 2245, 0.081597},
      {"2026-03-08T06:30:00Z", 50, 2480, 0.159722},
      {"2026-03-08T07:00:00Z", 70, 2915, 0.305556},
      {"2026-03-08T07:30:00Z", 90, 3315, 0.4375},
      {"2026-03-08T17:00:00Z", 70, 2915, 0.305556},
      {"2026-03-08T17:30:00Z", 50, 2480, 0.159722},
      {"2026-03-08T18:00:00Z", 30, 2000, 0.0},
      {"2026-03-08T18:15:00Z", 20, 2000, -0.081597},
      {"2026-03-08T18:30:00Z", 10, 2000, -0.159722}
    ])
  end

  test "tanh mode keeps the current asymmetric dark/light window behavior" do
    config =
      with_zero_curve_offsets(%{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 5000,
        "brightness_mode" => "tanh",
        "brightness_mode_time_dark" => 1800,
        "brightness_mode_time_light" => 5400
      })

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T05:30:00Z", 14, 2000, -0.159722},
      {"2026-03-08T05:45:00Z", 18, 2000, -0.081597},
      {"2026-03-08T06:00:00Z", 25, 2000, 0.0},
      {"2026-03-08T06:15:00Z", 36, 2245, 0.081597},
      {"2026-03-08T06:30:00Z", 50, 2480, 0.159722},
      {"2026-03-08T07:00:00Z", 75, 2915, 0.305556},
      {"2026-03-08T07:30:00Z", 86, 3315, 0.4375},
      {"2026-03-08T17:00:00Z", 75, 2915, 0.305556},
      {"2026-03-08T17:30:00Z", 50, 2480, 0.159722},
      {"2026-03-08T18:00:00Z", 25, 2000, 0.0},
      {"2026-03-08T18:15:00Z", 18, 2000, -0.081597},
      {"2026-03-08T18:30:00Z", 14, 2000, -0.159722}
    ])
  end

  test "brightness curve offsets shift only brightness reference outputs" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "min_brightness" => 10,
      "max_brightness" => 90,
      "min_color_temp" => 2000,
      "max_color_temp" => 5000,
      "brightness_mode" => "linear",
      "brightness_mode_time_dark" => 900,
      "brightness_mode_time_light" => 3600,
      "brightness_sunrise_offset" => 900,
      "brightness_sunset_offset" => -900,
      "temperature_sunrise_offset" => 0,
      "temperature_sunset_offset" => 0
    }

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T06:00:00Z", 10, 2000, 0.0},
      {"2026-03-08T06:15:00Z", 26, 2245, 0.081597},
      {"2026-03-08T17:45:00Z", 26, 2245, 0.081597},
      {"2026-03-08T18:00:00Z", 10, 2000, 0.0}
    ])
  end

  test "temperature curve offsets shift only kelvin reference outputs" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "min_brightness" => 10,
      "max_brightness" => 90,
      "min_color_temp" => 2000,
      "max_color_temp" => 5000,
      "brightness_mode" => "linear",
      "brightness_mode_time_dark" => 900,
      "brightness_mode_time_light" => 3600,
      "brightness_sunrise_offset" => 0,
      "brightness_sunset_offset" => 0,
      "temperature_sunrise_offset" => 1800,
      "temperature_sunset_offset" => -1800
    }

    assert_reference_outputs(config, @solar_utc, [
      {"2026-03-08T06:30:00Z", 58, 2000, 0.159722},
      {"2026-03-08T07:00:00Z", 90, 2520, 0.305556},
      {"2026-03-08T17:30:00Z", 58, 2000, 0.159722}
    ])
  end

  defp assert_reference_outputs(config, solar_config, cases) do
    Enum.each(cases, fn {iso8601, expected_brightness, expected_kelvin, expected_sun_position} ->
      assert {:ok, result} = Circadian.calculate(config, solar_config, utc_dt(iso8601))
      assert result.brightness == expected_brightness
      assert result.kelvin == expected_kelvin
      assert_in_delta result.sun_position, expected_sun_position, 1.0e-6
    end)
  end

  defp utc_dt(iso8601) do
    {:ok, datetime, 0} = DateTime.from_iso8601(iso8601)
    datetime
  end

  defp with_zero_curve_offsets(config) do
    Map.merge(
      %{
        "brightness_sunrise_offset" => 0,
        "brightness_sunset_offset" => 0,
        "temperature_sunrise_offset" => 0,
        "temperature_sunset_offset" => 0,
        "temperature_ceiling_kelvin" => nil
      },
      config
    )
  end
end
