defmodule Hueworks.CircadianTimingTest do
  use ExUnit.Case, async: true

  alias Hueworks.Circadian
  alias Hueworks.Circadian.Timing
  alias Hueworks.CircadianPreview

  @timezone "America/Los_Angeles"
  @location %{latitude: 47.6062, longitude: -122.3321, timezone: @timezone}
  @winter ~D[2026-12-21]
  @summer ~D[2026-06-21]

  # A realistic shared profile with local shaping stored for both events.
  @shaped_profile %{
    "min_brightness" => 10,
    "max_brightness" => 90,
    "min_color_temp" => 2000,
    "max_color_temp" => 4000,
    "temperature_ceiling_kelvin" => 3800,
    "brightness_mode" => "linear",
    "brightness_mode_time_dark" => 1800,
    "brightness_mode_time_light" => 7200,
    "sunrise_time" => "05:15:00",
    "min_sunrise_time" => "05:00:00",
    "max_sunrise_time" => "05:30:00",
    "sunrise_offset" => 600,
    "sunset_time" => "16:15:00",
    "min_sunset_time" => "16:00:00",
    "max_sunset_time" => "16:30:00",
    "sunset_offset" => -600,
    "brightness_sunrise_offset" => 300,
    "brightness_sunset_offset" => -300,
    "temperature_sunrise_offset" => 900,
    "temperature_sunset_offset" => -900
  }

  defp profile(sunrise_override, sunset_override, config \\ @shaped_profile) do
    Map.merge(config, %{
      "override_sunrise_timing" => sunrise_override,
      "override_sunset_timing" => sunset_override
    })
  end

  defp global(window \\ %{}), do: Map.merge(@location, window)

  defp events(config, solar_config, date, curve \\ :shared) do
    {:ok, events} = Circadian.day_events_for_date(config, solar_config, date, curve: curve)
    events
  end

  defp local_time(datetime) do
    datetime
    |> DateTime.shift_zone!(@timezone)
    |> DateTime.to_time()
    |> Time.truncate(:second)
  end

  defp local(date, time), do: DateTime.new!(date, time, @timezone)

  defp samples_for_day(config, solar_config, date) do
    for hour <- 0..23, minute <- [0, 20, 40] do
      {:ok, result} =
        Circadian.calculate(config, solar_config, local(date, Time.new!(hour, minute, 0)))

      {result.brightness, result.kelvin}
    end
  end

  describe "inherited events" do
    test "a global minimum holds back an early astronomical sunset" do
      solar_config = global(%{min_sunset_time: "18:00"})

      assert Time.compare(local_time(events(%{}, @location, @winter)[:sunset]), ~T[17:00:00]) ==
               :lt

      assert local_time(events(profile(false, false), solar_config, @winter)[:sunset]) ==
               ~T[18:00:00]
    end

    test "a global minimum lets a later summer sunset follow the sun" do
      solar_config = global(%{min_sunset_time: "18:00"})
      astronomical = events(%{}, @location, @summer)[:sunset]

      assert Time.compare(local_time(astronomical), ~T[18:00:00]) == :gt
      assert events(profile(false, false), solar_config, @summer)[:sunset] == astronomical
    end

    test "a global maximum pulls a late summer sunset forward" do
      solar_config = global(%{max_sunset_time: "20:00"})

      assert local_time(events(profile(false, false), solar_config, @summer)[:sunset]) ==
               ~T[20:00:00]
    end

    test "equal bounds pin the event to that time" do
      solar_config = global(%{min_sunrise_time: "07:15", max_sunrise_time: "07:15"})

      for date <- [@winter, @summer] do
        assert local_time(events(profile(false, false), solar_config, date)[:sunrise]) ==
                 ~T[07:15:00]
      end
    end

    test "stored timing has no effect with blank or populated globals" do
      unshaped = %{
        "min_brightness" => 10,
        "max_brightness" => 90,
        "min_color_temp" => 2000,
        "max_color_temp" => 4000,
        "temperature_ceiling_kelvin" => 3800,
        "brightness_mode" => "linear"
      }

      for solar_config <- [global(), global(%{min_sunset_time: "18:00"})],
          date <- [@winter, @summer] do
        for curve <- [:shared, :brightness, :temperature] do
          assert events(profile(false, false), solar_config, date, curve) ==
                   events(profile(false, false, unshaped), solar_config, date, curve)
        end

        assert samples_for_day(profile(false, false), solar_config, date) ==
                 samples_for_day(profile(false, false, unshaped), solar_config, date)
      end
    end

    test "blank globals leave an inheriting profile on astronomical anchors" do
      inherited = events(profile(false, false), global(), @winter)
      astronomical = events(%{}, @location, @winter)

      assert inherited == astronomical
      assert inherited[:noon] == astronomical[:noon]
      refute Timing.constrained?(resolve(profile(false, false), global()))
    end

    test "an effective global bound moves the noon anchor even when it does not bind" do
      solar_config = global(%{min_sunset_time: "10:00"})
      constrained = events(profile(false, false), solar_config, @winter)

      assert constrained[:sunset] == events(%{}, @location, @winter)[:sunset]

      assert DateTime.diff(constrained[:noon], constrained[:sunrise]) ==
               round(DateTime.diff(constrained[:sunset], constrained[:sunrise]) / 2)

      assert Timing.constrained?(resolve(profile(false, false), solar_config))
    end

    test "midnight is a real bound rather than a disabled value" do
      refute Timing.constrained?(resolve(profile(false, false), global()))

      assert Timing.constrained?(
               resolve(profile(false, false), global(%{min_sunset_time: "00:00"}))
             )
    end

    test "uses default ramp durations instead of stored durations" do
      solar_config = global(%{min_sunset_time: "18:00", min_sunrise_time: "07:00"})
      config = profile(false, false)

      # Linear ramp over 3600 s before and 900 s after sunset: 90 - 80 * 3600 / 4500.
      assert {:ok, %{brightness: 26}} =
               Circadian.calculate(config, solar_config, local(@winter, ~T[18:00:00]))

      # With the stored 7200/1800 ramp this instant would be at 26 + 16.
      assert {:ok, %{brightness: 90}} =
               Circadian.calculate(config, solar_config, local(@winter, ~T[17:00:00]))
    end

    test "brightness and temperature ranges stay per-profile" do
      solar_config = global(%{min_sunset_time: "18:00"})

      {:ok, midday} =
        Circadian.calculate(profile(false, false), solar_config, local(@summer, ~T[13:00:00]))

      {:ok, night} =
        Circadian.calculate(profile(false, false), solar_config, local(@summer, ~T[02:00:00]))

      assert midday.brightness == 90
      assert midday.kelvin == 3800
      assert night.brightness == 10
      assert night.kelvin == 2000
    end

    test "the brightness curve type stays per-profile" do
      quadratic = Map.put(@shaped_profile, "brightness_mode", "quadratic")
      solar_config = global(%{min_sunset_time: "18:00"})
      evening = local(@winter, ~T[19:00:00])

      {:ok, linear_result} = Circadian.calculate(profile(false, false), solar_config, evening)

      {:ok, quadratic_result} =
        Circadian.calculate(profile(false, false, quadratic), solar_config, evening)

      refute linear_result.brightness == quadratic_result.brightness
    end
  end

  describe "overridden events" do
    test "a missing flag keeps a legacy profile on local timing" do
      solar_config = global(%{min_sunset_time: "18:00", min_sunrise_time: "07:00"})

      for curve <- [:shared, :brightness, :temperature] do
        assert events(@shaped_profile, solar_config, @winter, curve) ==
                 events(profile(true, true), solar_config, @winter, curve)
      end

      assert samples_for_day(@shaped_profile, solar_config, @winter) ==
               samples_for_day(profile(true, true), solar_config, @winter)
    end

    test "global changes do not reach a fully overridden profile" do
      blank = samples_for_day(profile(true, true), global(), @winter)

      assert samples_for_day(
               profile(true, true),
               global(%{min_sunset_time: "18:00", max_sunrise_time: "04:00"}),
               @winter
             ) == blank
    end

    test "the local pair replaces the global pair rather than intersecting" do
      config =
        profile(true, true, %{
          "sunset_time" => "16:45:00",
          "sunrise_time" => "07:00:00",
          "min_sunset_time" => "17:00:00"
        })

      solar_config = global(%{min_sunset_time: "18:00", max_sunset_time: "20:00"})

      assert local_time(events(config, solar_config, @winter)[:sunset]) == ~T[17:00:00]
    end

    test "blank local bounds do not fall back to global bounds" do
      config = profile(true, true, %{"sunset_time" => "16:45:00", "sunrise_time" => "07:00:00"})
      solar_config = global(%{min_sunset_time: "18:00"})

      assert local_time(events(config, solar_config, @winter)[:sunset]) == ~T[16:45:00]
    end

    test "one local bound supplies only that bound" do
      config =
        profile(true, true, %{"max_sunset_time" => "16:00:00", "sunrise_time" => "07:00:00"})

      solar_config = global(%{min_sunset_time: "18:00"})

      assert local_time(events(config, solar_config, @summer)[:sunset]) == ~T[16:00:00]
    end

    test "the shared offset applies before clamping and a fixed time is still clamped" do
      config =
        profile(true, true, %{
          "sunrise_time" => "07:00:00",
          "sunset_time" => "18:15:00",
          "sunset_offset" => -1800,
          "min_sunset_time" => "18:00:00"
        })

      assert local_time(events(config, global(), @winter)[:sunset]) == ~T[18:00:00]
    end

    test "a curve offset can move that curve outside its shared local bounds" do
      config =
        profile(true, true, %{
          "sunrise_time" => "07:00:00",
          "sunset_time" => "19:00:00",
          "max_sunset_time" => "18:00:00",
          "brightness_sunset_offset" => 1800
        })

      assert local_time(events(config, global(), @winter, :shared)[:sunset]) == ~T[18:00:00]
      assert local_time(events(config, global(), @winter, :brightness)[:sunset]) == ~T[18:30:00]
    end

    test "the spec's stored negative offset example applies only when overriding" do
      stored =
        profile(false, false, %{
          "sunset_time" => "18:15:00",
          "sunset_offset" => -1800,
          "min_sunset_time" => "18:00:00"
        })

      # Summer astronomy stays later than the 18:00 global bound.
      astronomical = events(%{}, @location, @summer)[:sunset]

      assert events(stored, global(%{min_sunset_time: "18:00"}), @summer)[:sunset] == astronomical

      overridden = Map.put(stored, "override_sunset_timing", true)

      assert local_time(events(overridden, global(), @summer)[:sunset]) == ~T[18:00:00]
    end
  end

  describe "mixed inheritance" do
    @solar_bounds %{min_sunset_time: "18:00", min_sunrise_time: "07:00"}

    test "sunrise overrides while sunset inherits" do
      solar_config = global(@solar_bounds)
      config = profile(true, false)
      shared = events(config, solar_config, @winter)

      assert local_time(shared[:sunrise]) == ~T[05:25:00]
      assert local_time(shared[:sunset]) == ~T[18:00:00]

      brightness = events(config, solar_config, @winter, :brightness)
      assert local_time(brightness[:sunrise]) == ~T[05:30:00]
      assert local_time(brightness[:sunset]) == ~T[18:00:00]

      temperature = events(config, solar_config, @winter, :temperature)
      assert local_time(temperature[:sunrise]) == ~T[05:40:00]
      assert local_time(temperature[:sunset]) == ~T[18:00:00]
    end

    test "sunset overrides while sunrise inherits" do
      solar_config = global(@solar_bounds)
      config = profile(false, true)
      shared = events(config, solar_config, @winter)

      assert local_time(shared[:sunrise]) ==
               local_time(events(%{}, global(%{min_sunrise_time: "07:00"}), @winter)[:sunrise])

      assert local_time(shared[:sunset]) == ~T[16:05:00]

      brightness = events(config, solar_config, @winter, :brightness)
      assert brightness[:sunrise] == shared[:sunrise]
      assert local_time(brightness[:sunset]) == ~T[16:00:00]

      temperature = events(config, solar_config, @winter, :temperature)
      assert temperature[:sunrise] == shared[:sunrise]
      assert local_time(temperature[:sunset]) == ~T[15:50:00]
    end

    test "custom ramp durations apply only around the overridden event" do
      config =
        profile(true, false, %{
          "min_brightness" => 10,
          "max_brightness" => 90,
          "brightness_mode" => "linear",
          "brightness_mode_time_dark" => 1800,
          "brightness_mode_time_light" => 7200,
          "sunrise_time" => "07:00:00"
        })

      solar_config = global(%{min_sunset_time: "18:00"})

      # Overridden sunrise uses the stored ramp: 10 + 80 * (3600 + 1800) / 9000.
      assert {:ok, %{brightness: 58}} =
               Circadian.calculate(config, solar_config, local(@winter, ~T[08:00:00]))

      # Inherited sunset uses defaults: 90 - 80 * 3600 / 4500.
      assert {:ok, %{brightness: 26}} =
               Circadian.calculate(config, solar_config, local(@winter, ~T[18:00:00]))
    end

    test "custom ramp durations also follow an overridden sunset" do
      config =
        profile(false, true, %{
          "min_brightness" => 10,
          "max_brightness" => 90,
          "brightness_mode" => "linear",
          "brightness_mode_time_dark" => 1800,
          "brightness_mode_time_light" => 7200,
          "sunset_time" => "18:00:00"
        })

      solar_config = global(%{min_sunrise_time: "07:30", max_sunrise_time: "07:30"})

      # Overridden sunset uses the stored ramp: 90 - 80 * 7200 / 9000.
      assert {:ok, %{brightness: 26}} =
               Circadian.calculate(config, solar_config, local(@winter, ~T[18:00:00]))

      # Inherited sunrise uses defaults: 10 + 80 * 900 / 4500.
      assert {:ok, %{brightness: 26}} =
               Circadian.calculate(config, solar_config, local(@winter, ~T[07:30:00]))
    end

    test "an ignored fixed time in the inherited event does not constrain the anchors" do
      config =
        profile(false, false, %{"sunset_time" => "16:00:00", "max_sunrise_time" => "06:00:00"})

      refute Timing.constrained?(resolve(config, global()))
      assert events(config, global(), @winter)[:noon] == events(%{}, @location, @winter)[:noon]
    end
  end

  describe "preview and runtime agreement" do
    for {sunrise, sunset} <- [{false, false}, {true, false}, {false, true}, {true, true}],
        window <- [%{}, %{min_sunset_time: "18:00", max_sunrise_time: "08:00"}] do
      @sunrise sunrise
      @sunset sunset
      @window window

      test "samples and markers match for sunrise=#{sunrise} sunset=#{sunset} window=#{inspect(window)}" do
        config = profile(@sunrise, @sunset)
        solar_config = global(@window)

        assert {:ok, preview} =
                 CircadianPreview.sample_day(config, solar_config, @winter, interval_minutes: 30)

        for point <- preview.points do
          time = Time.new!(div(point.minute, 60), rem(point.minute, 60), 0)
          {:ok, direct} = Circadian.calculate(config, solar_config, local(@winter, time))

          assert {point.brightness, point.kelvin} == {direct.brightness, direct.kelvin}
        end

        for {markers, curve} <- [
              {preview.markers, :shared},
              {preview.brightness_markers, :brightness},
              {preview.temperature_markers, :temperature}
            ],
            marker <- markers do
          direct = events(config, solar_config, @winter, curve)[marker.key]

          assert marker.time_label ==
                   direct |> local_time() |> Time.to_iso8601() |> String.slice(0, 5)
        end
      end
    end

    test "the preview does not drop global bounds from its solar config" do
      config = profile(false, false)

      assert {:ok, preview} =
               CircadianPreview.sample_day(
                 config,
                 global(%{min_sunset_time: "18:00"}),
                 @winter,
                 interval_minutes: 60
               )

      assert Enum.find(preview.markers, &(&1.key == :sunset)).time_label == "18:00"
      assert Enum.find(preview.temperature_markers, &(&1.key == :sunset)).time_label == "18:00"
    end

    test "the preview samples the requested local date across the date line" do
      solar_config = %{latitude: 1.87, longitude: -157.4, timezone: "Pacific/Kiritimati"}

      assert {:ok, preview} =
               CircadianPreview.sample_day(
                 profile(false, false),
                 Map.put(solar_config, :min_sunset_time, "18:00"),
                 ~D[2026-12-21],
                 interval_minutes: 60
               )

      assert Enum.map(preview.markers, & &1.key) == [:sunrise, :noon, :sunset]
    end

    test "the preview returns astronomical unavailability as an error" do
      solar_config = %{latitude: 69.6492, longitude: 18.9553, timezone: "Europe/Oslo"}

      assert {:error, {:sun_event_unavailable, :sunrise, ~D[2026-06-21]}} =
               CircadianPreview.sample_day(profile(false, false), solar_config, ~D[2026-06-21])
    end
  end

  describe "daylight saving" do
    test "a global bound stays on the local wall clock across both transitions" do
      solar_config = global(%{min_sunset_time: "19:30", max_sunrise_time: "06:30"})

      for date <- [~D[2026-03-07], ~D[2026-03-08], ~D[2026-10-31], ~D[2026-11-01]] do
        shared = events(profile(false, false), solar_config, date)

        assert local_time(shared[:sunset]) == ~T[19:30:00]
        assert local_time(shared[:sunrise]) == ~T[06:30:00]
      end
    end
  end

  describe "failures" do
    test "the order check keeps the existing cyclic day" do
      crossed = global(%{min_sunrise_time: "19:00", max_sunset_time: "18:00"})

      refute Circadian.invalid_event_order?(profile(false, false), crossed, @winter)

      assert {:ok, _result} =
               Circadian.calculate(profile(false, false), crossed, local(@winter, ~T[12:00:00]))
    end

    test "a global window rejects a fraction or offset" do
      for value <- ["18:00:00.5", "18:00:00+05:00", "18:00:00Z"] do
        assert {:error, {:invalid_global_window, :min_sunset_time}} =
                 Circadian.calculate(
                   %{},
                   global(%{min_sunset_time: value}),
                   ~U[2026-03-08 12:00:00Z]
                 )
      end
    end

    test "a malformed or inverted global window is an error" do
      assert {:error, {:invalid_global_window, :min_sunset_time}} =
               Circadian.calculate(
                 %{},
                 global(%{min_sunset_time: "late"}),
                 ~U[2026-03-08 12:00:00Z]
               )

      assert {:error, {:invalid_global_window, :min_sunset_time}} =
               Circadian.calculate(
                 %{},
                 global(%{min_sunset_time: "20:00", max_sunset_time: "18:00"}),
                 ~U[2026-03-08 12:00:00Z]
               )
    end

    test "a zero-width ramp is an error rather than a crash" do
      config = %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "brightness_mode_time_dark" => 0,
        "brightness_mode_time_light" => 0
      }

      assert {:error, {:zero_width_brightness_ramp, _event}} =
               Circadian.calculate(config, global(), ~U[2026-03-08 20:00:00Z])
    end

    test "invalid_event_order? reports ordering but not astronomical unavailability" do
      ordering_conflict = %{
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00",
        "brightness_sunrise_offset" => 36_000,
        "brightness_sunset_offset" => -36_000
      }

      assert Circadian.invalid_event_order?(ordering_conflict, global(), @winter)
      refute Circadian.invalid_event_order?(%{}, global(), @winter)

      refute Circadian.invalid_event_order?(
               %{},
               %{latitude: 69.6492, longitude: 18.9553, timezone: "Europe/Oslo"},
               ~D[2026-06-21]
             )
    end
  end

  defp resolve(config, solar_config) do
    {:ok, inputs} = Circadian.prepare(config, solar_config)
    inputs.timing
  end
end
