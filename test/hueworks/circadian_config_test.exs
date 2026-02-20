defmodule Hueworks.CircadianConfigTest do
  use ExUnit.Case, async: true

  alias Hueworks.Circadian.Config

  test "normalize accepts supported keys and coerces values" do
    assert {:ok, normalized} =
             Config.normalize(%{
               "min_brightness" => "10",
               "max_brightness" => 90,
               "min_color_temp" => "2200",
               "max_color_temp" => 5000.0,
               "sunrise_time" => "06:30",
               "min_sunrise_time" => "05:00:00",
               "max_sunrise_time" => "07:15",
               "sunrise_offset" => "-00:30",
               "sunset_time" => "18:45",
               "sunset_offset" => "00:15:30",
               "brightness_mode" => "linear",
               "brightness_mode_time_dark" => "00:10:00",
               "brightness_mode_time_light" => "7200"
             })

    assert normalized["min_brightness"] == 10
    assert normalized["max_brightness"] == 90
    assert normalized["min_color_temp"] == 2200
    assert normalized["max_color_temp"] == 5000
    assert normalized["sunrise_time"] == "06:30:00"
    assert normalized["min_sunrise_time"] == "05:00:00"
    assert normalized["max_sunrise_time"] == "07:15:00"
    assert normalized["sunrise_offset"] == -1800
    assert normalized["sunset_time"] == "18:45:00"
    assert normalized["sunset_offset"] == 930
    assert normalized["brightness_mode"] == "linear"
    assert normalized["brightness_mode_time_dark"] == 600
    assert normalized["brightness_mode_time_light"] == 7200
  end

  test "normalize rejects unsupported, sleep, and rgb keys" do
    assert {:error, errors} =
             Config.normalize(%{
               "sleep_brightness" => 1,
               "prefer_rgb_color" => true,
               "custom_key" => "value"
             })

    assert {"sleep_brightness", "is not supported"} in errors
    assert {"prefer_rgb_color", "is not supported"} in errors
    assert {"custom_key", "is not supported"} in errors
  end

  test "normalize enforces min/max ordering and time windows" do
    assert {:error, errors} =
             Config.normalize(%{
               "min_brightness" => 70,
               "max_brightness" => 20,
               "min_color_temp" => 6000,
               "max_color_temp" => 2500,
               "min_sunrise_time" => "08:00",
               "max_sunrise_time" => "06:00"
             })

    assert {"min_brightness", "must be less than or equal to max_brightness"} in errors
    assert {"max_brightness", "must be greater than or equal to min_brightness"} in errors
    assert {"min_color_temp", "must be less than or equal to max_color_temp"} in errors
    assert {"max_color_temp", "must be greater than or equal to min_color_temp"} in errors
    assert {"min_sunrise_time", "must be less than or equal to max_sunrise_time"} in errors
    assert {"max_sunrise_time", "must be greater than or equal to min_sunrise_time"} in errors
  end
end
