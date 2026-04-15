defmodule Hueworks.CircadianPreviewTest do
  use ExUnit.Case, async: true

  alias Hueworks.CircadianPreview

  @solar_config %{latitude: 40.7128, longitude: -74.0060, timezone: "Etc/UTC"}

  test "samples a full day with points and sun-event markers" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "min_brightness" => 1,
      "max_brightness" => 100,
      "min_color_temp" => 2000,
      "max_color_temp" => 5500
    }

    assert {:ok, preview} =
             CircadianPreview.sample_day(config, @solar_config, ~D[2026-03-08],
               interval_minutes: 60
             )

    assert preview.timezone == "Etc/UTC"
    assert preview.date == ~D[2026-03-08]
    assert preview.interval_minutes == 60
    assert preview.config[:brightness_mode] == :tanh
    assert preview.config[:min_brightness] == 1
    assert length(preview.points) == 25

    assert hd(preview.points) == %{minute: 0, brightness: 1, kelvin: 2000}

    assert Enum.find(preview.points, &(&1.minute == 720)) == %{
             minute: 720,
             brightness: 100,
             kelvin: 5500
           }

    assert List.last(preview.points).minute == 1439

    assert Enum.map(preview.markers, & &1.key) == [:sunrise, :noon, :sunset]
    assert Enum.map(preview.brightness_markers, & &1.key) == [:sunrise, :noon, :sunset]
    assert Enum.map(preview.temperature_markers, & &1.key) == [:sunrise, :noon, :sunset]
    assert Enum.find(preview.markers, &(&1.key == :sunrise)).time_label == "06:00"
    assert Enum.find(preview.markers, &(&1.key == :sunset)).time_label == "18:00"
    assert Enum.find(preview.markers, &(&1.key == :noon)).time_label == "12:00"
  end

  test "builds separate markers for brightness and temperature offsets" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "brightness_sunrise_offset" => 900,
      "brightness_sunset_offset" => -900,
      "temperature_sunrise_offset" => 1800,
      "temperature_sunset_offset" => -1800
    }

    assert {:ok, preview} =
             CircadianPreview.sample_day(config, @solar_config, ~D[2026-03-08],
               interval_minutes: 60
             )

    assert Enum.find(preview.markers, &(&1.key == :sunrise)).time_label == "06:00"
    assert Enum.find(preview.brightness_markers, &(&1.key == :sunrise)).time_label == "06:15"
    assert Enum.find(preview.brightness_markers, &(&1.key == :sunset)).time_label == "17:45"
    assert Enum.find(preview.temperature_markers, &(&1.key == :sunrise)).time_label == "06:30"
    assert Enum.find(preview.temperature_markers, &(&1.key == :sunset)).time_label == "17:30"
  end

  test "uses the temperature ceiling as the effective preview maximum and flattens midday points" do
    config = %{
      "sunrise_time" => "06:00:00",
      "sunset_time" => "18:00:00",
      "min_color_temp" => 2000,
      "max_color_temp" => 5500,
      "temperature_ceiling_kelvin" => 4500
    }

    assert {:ok, preview} =
             CircadianPreview.sample_day(config, @solar_config, ~D[2026-03-08],
               interval_minutes: 120
             )

    assert preview.min_kelvin == 2000
    assert preview.max_kelvin == 4500
    assert Enum.find(preview.points, &(&1.minute == 600)).kelvin == 4500
    assert Enum.find(preview.points, &(&1.minute == 720)).kelvin == 4500
  end

  test "returns a useful error when solar inputs are incomplete" do
    assert {:error, :missing_latitude} =
             CircadianPreview.sample_day(
               %{},
               %{longitude: -74.0, timezone: "Etc/UTC"},
               ~D[2026-03-08]
             )
  end
end
