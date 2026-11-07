defmodule Hueworks.CircadianCalendarTest do
  use ExUnit.Case, async: true

  alias Hueworks.Circadian

  @kiritimati %{latitude: 1.87, longitude: -157.4, timezone: "Pacific/Kiritimati"}
  @tromso %{latitude: 69.6492, longitude: 18.9553, timezone: "Europe/Oslo"}
  @los_angeles %{latitude: 47.6062, longitude: -122.3321, timezone: "America/Los_Angeles"}

  describe "local calendar date" do
    test "resolves astronomical events on the requested date across the date line" do
      assert {:ok, events} =
               Circadian.day_events_for_date(
                 %{"min_sunset_time" => "18:00"},
                 @kiritimati,
                 ~D[2026-12-21]
               )

      assert local_date(events[:sunrise], @kiritimati) == ~D[2026-12-21]
      assert local_date(events[:sunset], @kiritimati) == ~D[2026-12-21]
      assert local_date(events[:noon], @kiritimati) == ~D[2026-12-21]
    end

    test "uses the same local day for a calculation near a UTC date boundary" do
      evening = DateTime.new!(~D[2026-12-21], ~T[23:30:00], "Pacific/Kiritimati")
      morning = DateTime.new!(~D[2026-12-21], ~T[00:30:00], "Pacific/Kiritimati")

      assert {:ok, %{sun_position: evening_position}} =
               Circadian.calculate(%{}, @kiritimati, evening)

      assert {:ok, %{sun_position: morning_position}} =
               Circadian.calculate(%{}, @kiritimati, morning)

      assert evening_position < 0
      assert morning_position < 0
    end

    test "keeps a fixed local time on the requested date west of UTC late in the evening" do
      config = %{"sunrise_time" => "07:00:00", "sunset_time" => "17:00:00"}

      assert {:ok, events} =
               Circadian.day_events_for_date(config, @los_angeles, ~D[2026-12-21])

      assert local_time(events[:sunrise], @los_angeles) == ~T[07:00:00]
      assert local_time(events[:sunset], @los_angeles) == ~T[17:00:00]
      assert local_date(events[:sunset], @los_angeles) == ~D[2026-12-21]
    end
  end

  describe "daylight saving transitions" do
    test "a nonexistent local bound uses the instant after the spring-forward gap" do
      assert {:ok, events} =
               Circadian.day_events_for_date(
                 %{
                   "sunrise_time" => "02:30:00",
                   "sunset_time" => "18:00:00",
                   "max_sunrise_time" => "02:30:00"
                 },
                 @los_angeles,
                 ~D[2026-03-08]
               )

      assert local_time(events[:sunrise], @los_angeles) == ~T[03:00:00]
    end

    test "an ambiguous local bound uses the first occurrence on the fall-back day" do
      assert {:ok, events} =
               Circadian.day_events_for_date(
                 %{
                   "sunrise_time" => "01:30:00",
                   "sunset_time" => "18:00:00",
                   "min_sunrise_time" => "01:30:00"
                 },
                 @los_angeles,
                 ~D[2026-11-01]
               )

      assert DateTime.shift_zone!(events[:sunrise], "America/Los_Angeles").std_offset == 3600
    end

    test "astronomical calculations stay on the local day through both transitions" do
      for date <- [~D[2026-03-08], ~D[2026-11-01]] do
        assert {:ok, events} = Circadian.day_events_for_date(%{}, @los_angeles, date)
        assert local_date(events[:sunrise], @los_angeles) == date
        assert local_date(events[:sunset], @los_angeles) == date
      end
    end
  end

  describe "astronomical unavailability" do
    test "a polar neighboring day returns an error instead of raising" do
      local_noon = DateTime.new!(~D[2026-05-17], ~T[12:00:00], "Europe/Oslo")

      assert {:error, {:sun_event_unavailable, event, date}} =
               Circadian.calculate(%{}, @tromso, local_noon)

      assert event in [:sunrise, :sunset]
      assert date in [~D[2026-05-16], ~D[2026-05-17], ~D[2026-05-18]]
    end

    test "a polar day returns an error for events on that date" do
      assert {:error, {:sun_event_unavailable, :sunrise, ~D[2026-06-21]}} =
               Circadian.day_events_for_date(%{}, @tromso, ~D[2026-06-21])
    end

    test "fixed local times do not need the astronomical event on a polar day" do
      config = %{"sunrise_time" => "06:00:00", "sunset_time" => "20:00:00"}
      local_noon = DateTime.new!(~D[2026-06-21], ~T[12:00:00], "Europe/Oslo")

      assert {:ok, %{brightness: 100}} = Circadian.calculate(config, @tromso, local_noon)
    end

    test "an unknown timezone returns an error instead of raising" do
      solar_config = %{latitude: 40.0, longitude: -74.0, timezone: "Mars/Olympus_Mons"}

      assert {:error, _reason} =
               Circadian.calculate(%{}, solar_config, ~U[2026-03-08 12:00:00Z])

      assert {:error, _reason} =
               Circadian.day_events_for_date(
                 %{"max_sunset_time" => "20:00"},
                 solar_config,
                 ~D[2026-03-08]
               )
    end
  end

  defp local_date(datetime, %{timezone: timezone}) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_date()
  end

  defp local_time(datetime, %{timezone: timezone}) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_time()
    |> Time.truncate(:second)
  end
end
