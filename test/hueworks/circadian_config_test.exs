defmodule Hueworks.CircadianConfigTest do
  use ExUnit.Case, async: true

  alias Hueworks.Circadian.Config

  describe "timing override flags" do
    test "false and true survive load, runtime, normalize, and dump" do
      for flag <- [false, true] do
        config = %{"override_sunrise_timing" => flag, "override_sunset_timing" => flag}

        assert {:ok, loaded} = Config.load(config)
        assert loaded.override_sunrise_timing == flag
        assert Config.dump(loaded)["override_sunset_timing"] == flag

        assert {:ok, normalized} = Config.normalize(config)
        assert normalized["override_sunrise_timing"] == flag

        assert {:ok, runtime} = Config.runtime(config)
        assert runtime[:override_sunset_timing] == flag

        assert {:ok, struct_runtime} = Config.runtime(loaded)
        assert struct_runtime[:override_sunset_timing] == flag
      end
    end

    test "form strings parse to booleans" do
      assert {:ok, %{"override_sunset_timing" => false}} =
               Config.normalize(%{"override_sunset_timing" => "false"})

      assert {:ok, %{"override_sunset_timing" => true}} =
               Config.normalize(%{"override_sunset_timing" => "true"})
    end

    test "missing flags resolve to legacy local timing" do
      assert {:ok, runtime} = Config.runtime(%{})
      assert runtime[:override_sunrise_timing] == true
      assert runtime[:override_sunset_timing] == true

      assert {:ok, loaded} = Config.load(%{})
      refute Map.has_key?(Config.dump(loaded), "override_sunrise_timing")
    end

    test "new profile config is explicit inheritance" do
      assert Config.new_profile_config() == %{
               "override_sunrise_timing" => false,
               "override_sunset_timing" => false
             }
    end

    test "rejects a malformed flag" do
      assert {:error, [{"override_sunset_timing", "must be true or false"}]} =
               Config.load(%{"override_sunset_timing" => "sometimes"})
    end
  end

  describe "local windows" do
    @inverted %{"min_sunset_time" => "20:00:00", "max_sunset_time" => "18:00:00"}

    test "an inverted window loads while its event inherits" do
      config = Map.put(@inverted, "override_sunset_timing", false)

      assert {:ok, loaded} = Config.load(config)
      assert loaded.min_sunset_time == "20:00:00"
      assert {:ok, runtime} = Config.runtime(config)
      assert runtime[:max_sunset_time] == "18:00:00"
    end

    test "an inverted window is rejected while its event overrides" do
      config = Map.put(@inverted, "override_sunset_timing", true)

      assert {:error, errors} = Config.load(config)
      assert Enum.any?(errors, &match?({"min_sunset_time", _message}, &1))
    end

    test "an inverted window is rejected when the flag is missing" do
      assert {:error, _errors} = Config.load(@inverted)
      assert {:error, _errors} = Config.runtime(@inverted)
    end

    test "inheriting one event does not exempt the other" do
      config = %{
        "override_sunset_timing" => false,
        "min_sunrise_time" => "09:00:00",
        "max_sunrise_time" => "06:00:00"
      }

      assert {:error, errors} = Config.load(config)
      assert Enum.any?(errors, &match?({"min_sunrise_time", _message}, &1))
    end

    test "profile times keep their looser parsing" do
      assert {:ok, %{"sunset_time" => "18:00:00"}} =
               Config.normalize(%{"sunset_time" => "18:00:00Z"})

      assert {:ok, %{"sunset_time" => "18:00:00.5"}} =
               Config.normalize(%{"sunset_time" => "18:00:00.5"})
    end
  end

  describe "global bound parsing" do
    for {value, expected} <- [
          {"18:00", "18:00:00"},
          {"18:00:30", "18:00:30"},
          {"00:00", "00:00:00"},
          {" 18:00 ", "18:00:00"},
          {"", nil},
          {"None", nil},
          {nil, nil}
        ] do
      test "accepts #{inspect(value)}" do
        assert Config.normalize_wall_clock_time(unquote(value)) == {:ok, unquote(expected)}
      end
    end

    for value <- [
          "18:00:00.5",
          "18:00:00,5",
          "18:00:00+05:00",
          "18:00:00-08:00",
          "18:00:00Z",
          "T18:00:00",
          "7:30",
          "24:00",
          "18:60",
          "18:00:60",
          "   ",
          "none",
          "evening"
        ] do
      test "rejects #{inspect(value)}" do
        assert {:error, _message} = Config.normalize_wall_clock_time(unquote(value))
      end
    end

    test "rejects non-strings" do
      assert {:error, _message} = Config.normalize_wall_clock_time(1800)
    end
  end

  test "normalize accepts supported keys and coerces values" do
    assert {:ok, normalized} =
             Config.normalize(%{
               "min_brightness" => "10",
               "max_brightness" => 90,
               "min_color_temp" => "2200",
               "max_color_temp" => 5000.0,
               "temperature_ceiling_kelvin" => "4200",
               "sunrise_time" => "06:30",
               "min_sunrise_time" => "05:00:00",
               "max_sunrise_time" => "07:15",
               "sunrise_offset" => "-00:30",
               "sunset_time" => "18:45",
               "sunset_offset" => "00:15:30",
               "brightness_mode" => "linear",
               "brightness_mode_time_dark" => "00:10:00",
               "brightness_mode_time_light" => "7200",
               "brightness_sunrise_offset" => "-300",
               "brightness_sunset_offset" => "600",
               "temperature_sunrise_offset" => "-00:05:00",
               "temperature_sunset_offset" => "00:10:00"
             })

    assert normalized["min_brightness"] == 10
    assert normalized["max_brightness"] == 90
    assert normalized["min_color_temp"] == 2200
    assert normalized["max_color_temp"] == 5000
    assert normalized["temperature_ceiling_kelvin"] == 4200
    assert normalized["sunrise_time"] == "06:30:00"
    assert normalized["min_sunrise_time"] == "05:00:00"
    assert normalized["max_sunrise_time"] == "07:15:00"
    assert normalized["sunrise_offset"] == -1800
    assert normalized["sunset_time"] == "18:45:00"
    assert normalized["sunset_offset"] == 930
    assert normalized["brightness_mode"] == "linear"
    assert normalized["brightness_mode_time_dark"] == 600
    assert normalized["brightness_mode_time_light"] == 7200
    assert normalized["brightness_sunrise_offset"] == -300
    assert normalized["brightness_sunset_offset"] == 600
    assert normalized["temperature_sunrise_offset"] == -300
    assert normalized["temperature_sunset_offset"] == 600
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

  test "normalize allows a blank temperature ceiling and rejects values outside the temperature range" do
    assert {:ok, normalized} =
             Config.normalize(%{
               "min_color_temp" => 2200,
               "max_color_temp" => 5000,
               "temperature_ceiling_kelvin" => ""
             })

    assert normalized["temperature_ceiling_kelvin"] == nil

    assert {:error, errors} =
             Config.normalize(%{
               "min_color_temp" => 2200,
               "max_color_temp" => 5000,
               "temperature_ceiling_kelvin" => 2000
             })

    assert {"temperature_ceiling_kelvin", "must be greater than or equal to min_color_temp"} in errors

    assert {:error, errors} =
             Config.normalize(%{
               "min_color_temp" => 2200,
               "max_color_temp" => 5000,
               "temperature_ceiling_kelvin" => 5200
             })

    assert {"temperature_ceiling_kelvin", "must be less than or equal to max_color_temp"} in errors
  end

  test "runtime returns a default-merged atom-keyed config for downstream consumers" do
    assert {:ok, runtime} =
             Config.runtime(%{
               "brightness_mode" => "linear",
               "min_brightness" => "10",
               "sunrise_time" => "06:30"
             })

    assert runtime[:brightness_mode] == :linear
    assert runtime[:min_brightness] == 10
    assert runtime[:max_brightness] == 100
    assert runtime[:sunrise_time] == "06:30:00"
    assert runtime[:temperature_ceiling_kelvin] == nil
  end

  test "load returns a typed circadian config struct" do
    assert {:ok, %Config{} = config} =
             Config.load(%{
               "brightness_mode" => "linear",
               "min_brightness" => "10",
               "sunrise_time" => "06:30"
             })

    assert config.brightness_mode == :linear
    assert config.min_brightness == 10
    assert config.sunrise_time == "06:30:00"
  end
end
