defmodule Hueworks.LightStateTimingTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.AppSettings
  alias Hueworks.Circadian
  alias Hueworks.CircadianPreview
  alias Hueworks.Scenes
  alias Hueworks.Schemas.LightState

  @stored_timing %{
    "sunset_time" => "17:30:00",
    "min_sunset_time" => "17:00:00",
    "max_sunset_time" => "18:00:00",
    "sunset_offset" => -300,
    "brightness_sunset_offset" => 120,
    "temperature_sunset_offset" => -120,
    "brightness_mode_time_dark" => 1800,
    "brightness_mode_time_light" => 7200
  }

  setup do
    {:ok, _settings} =
      AppSettings.upsert_global(%{
        latitude: 47.6062,
        longitude: -122.3321,
        timezone: "America/Los_Angeles"
      })

    :ok
  end

  defp persisted(%LightState{id: id}) do
    LightState
    |> Repo.get!(id)
    |> LightState.persisted_config()
  end

  test "a new circadian profile explicitly inherits both events" do
    {:ok, state} = Scenes.create_light_state("Default Circadian", :circadian, %{})

    assert persisted(state) == %{
             "override_sunrise_timing" => false,
             "override_sunset_timing" => false
           }
  end

  test "creation respects explicitly supplied flags, including atom keys" do
    {:ok, state} =
      Scenes.create_light_state("Foyer", :circadian, %{
        override_sunrise_timing: true,
        override_sunset_timing: false
      })

    config = persisted(state)

    assert config["override_sunrise_timing"] == true
    assert config["override_sunset_timing"] == false
  end

  test "a manual state has no timing flags" do
    {:ok, state} =
      Scenes.create_light_state("Soft", :manual, %{"brightness" => 40, "temperature" => 3000})

    refute Map.has_key?(persisted(state), "override_sunrise_timing")
  end

  test "a legacy payload without flags keeps local behavior and stays unflagged" do
    state =
      Repo.insert!(%LightState{
        name: "Legacy",
        type: :circadian,
        config: %{sunrise_time: "06:00:00", sunset_time: "18:30:00"}
      })

    refute Map.has_key?(persisted(state), "override_sunset_timing")

    config = LightState.circadian_config(Repo.get!(LightState, state.id))

    {:ok, events} =
      Circadian.day_events_for_date(
        config,
        %{timezone: "America/Los_Angeles", min_sunset_time: "20:00"},
        ~D[2026-12-21]
      )

    assert events[:sunset] ==
             DateTime.new!(~D[2026-12-21], ~T[18:30:00], "America/Los_Angeles")
             |> DateTime.shift_zone!("Etc/UTC")
  end

  test "false and true both survive reloads and unrelated updates" do
    {:ok, state} =
      Scenes.create_light_state("Mixed", :circadian, %{
        "override_sunrise_timing" => true,
        "override_sunset_timing" => false
      })

    {:ok, updated} = Scenes.update_light_state(state.id, %{name: "Renamed"})
    assert persisted(updated)["override_sunrise_timing"] == true
    assert persisted(updated)["override_sunset_timing"] == false

    {:ok, updated} =
      Scenes.update_light_state(state.id, %{config: %{"min_brightness" => 20}})

    assert persisted(updated)["override_sunrise_timing"] == true
    assert persisted(updated)["override_sunset_timing"] == false
    assert persisted(updated)["min_brightness"] == 20
  end

  test "inheriting keeps stored local values and overriding restores them" do
    {:ok, state} =
      Scenes.create_light_state(
        "Stored",
        :circadian,
        Map.put(@stored_timing, "override_sunset_timing", true)
      )

    {:ok, inheriting} =
      Scenes.update_light_state(state.id, %{config: %{"override_sunset_timing" => false}})

    assert Map.take(persisted(inheriting), Map.keys(@stored_timing)) == @stored_timing

    {:ok, restored} =
      Scenes.update_light_state(state.id, %{config: %{"override_sunset_timing" => true}})

    assert Map.take(persisted(restored), Map.keys(@stored_timing)) == @stored_timing

    {:ok, events} =
      Circadian.day_events_for_date(
        LightState.circadian_config(restored),
        AppSettings.solar_config(),
        ~D[2026-12-21]
      )

    assert events[:sunset] ==
             ~D[2026-12-21]
             |> DateTime.new!(~T[17:25:00], "America/Los_Angeles")
             |> DateTime.shift_zone!("Etc/UTC")
  end

  test "duplicating preserves flags and stored local values" do
    {:ok, state} =
      Scenes.create_light_state(
        "Original",
        :circadian,
        Map.merge(@stored_timing, %{
          "override_sunrise_timing" => true,
          "override_sunset_timing" => false
        })
      )

    {:ok, copy} = Scenes.duplicate_light_state(state.id)

    assert copy.name == "Original Copy"
    assert persisted(copy) == persisted(state)
    assert persisted(copy)["override_sunset_timing"] == false
  end

  test "duplicating a legacy profile keeps it on local timing" do
    state =
      Repo.insert!(%LightState{
        name: "Legacy",
        type: :circadian,
        config: %{sunset_time: "18:30:00"}
      })

    {:ok, copy} = Scenes.duplicate_light_state(state.id)

    assert persisted(copy)["sunset_time"] == "18:30:00"
    refute persisted(copy)["override_sunset_timing"] == false
  end

  test "rejects a profile edit that breaks its own event order and names it" do
    {:ok, state} =
      Scenes.create_light_state("Default Circadian", :circadian, %{
        "override_sunrise_timing" => true,
        "override_sunset_timing" => true,
        "sunrise_time" => "06:00:00",
        "sunset_time" => "18:00:00"
      })

    assert {:error, changeset} =
             Scenes.update_light_state(state.id, %{
               config: %{
                 "brightness_sunrise_offset" => 36_000,
                 "brightness_sunset_offset" => -36_000
               }
             })

    assert {message, _opts} = changeset.errors[:config]
    assert message =~ "Default Circadian"
    assert persisted(state)["brightness_sunrise_offset"] == nil
  end

  test "rejects creating a profile with an impossible event order" do
    assert {:error, changeset} =
             Scenes.create_light_state("Impossible", :circadian, %{
               "override_sunrise_timing" => true,
               "override_sunset_timing" => true,
               "sunrise_time" => "06:00:00",
               "sunset_time" => "18:00:00",
               "brightness_sunrise_offset" => 36_000,
               "brightness_sunset_offset" => -36_000
             })

    assert {message, _opts} = changeset.errors[:config]
    assert message =~ "Impossible"
    refute Repo.get_by(LightState, name: "Impossible")
  end

  test "an unrelated edit of an already broken profile stays possible" do
    state =
      Repo.insert!(%LightState{
        name: "Already Broken",
        type: :circadian,
        config: %{
          sunrise_time: "06:00:00",
          sunset_time: "18:00:00",
          brightness_sunrise_offset: 36_000,
          brightness_sunset_offset: -36_000
        }
      })

    assert {:ok, updated} = Scenes.update_light_state(state.id, %{name: "Still Broken"})
    assert updated.name == "Still Broken"
  end

  describe "a dormant inverted local window" do
    @inverted_sunset %{"min_sunset_time" => "20:00:00", "max_sunset_time" => "18:00:00"}

    test "is retained while its event inherits" do
      {:ok, state} = Scenes.create_light_state("Dormant", :circadian, @inverted_sunset)

      assert Map.take(persisted(state), Map.keys(@inverted_sunset)) == @inverted_sunset

      {:ok, renamed} = Scenes.update_light_state(state.id, %{name: "Still Dormant"})
      assert Map.take(persisted(renamed), Map.keys(@inverted_sunset)) == @inverted_sunset
    end

    test "a legacy row holding one stays editable" do
      state =
        Repo.insert!(%LightState{
          name: "Legacy Dormant",
          type: :circadian,
          config: %{
            override_sunset_timing: false,
            min_sunset_time: "20:00:00",
            max_sunset_time: "18:00:00"
          }
        })

      assert {:ok, updated} =
               Scenes.update_light_state(state.id, %{config: %{"min_brightness" => 20}})

      assert persisted(updated)["min_brightness"] == 20
      assert persisted(updated)["min_sunset_time"] == "20:00:00"
    end

    test "has no effect on runtime or preview" do
      solar_config = Map.put(AppSettings.solar_config(), :min_sunset_time, "18:00:00")
      {:ok, state} = Scenes.create_light_state("Dormant", :circadian, @inverted_sunset)
      stored = persisted(state)
      inherited = %{"override_sunrise_timing" => false, "override_sunset_timing" => false}
      now = DateTime.new!(~D[2026-12-21], ~T[17:15:00], "America/Los_Angeles")

      assert {:ok, expected} = Circadian.calculate(inherited, solar_config, now)
      assert Circadian.calculate(stored, solar_config, now) == {:ok, expected}

      assert Circadian.calculate(LightState.circadian_config(state), solar_config, now) ==
               {:ok, expected}

      assert {:ok, preview} =
               CircadianPreview.sample_day(stored, solar_config, ~D[2026-12-21],
                 interval_minutes: 60
               )

      assert {:ok, inherited_preview} =
               CircadianPreview.sample_day(inherited, solar_config, ~D[2026-12-21],
                 interval_minutes: 60
               )

      assert preview.points == inherited_preview.points
      assert preview.markers == inherited_preview.markers
    end

    test "is rejected when its override is re-enabled" do
      {:ok, state} = Scenes.create_light_state("Dormant", :circadian, @inverted_sunset)

      assert {:error, changeset} =
               Scenes.update_light_state(state.id, %{config: %{"override_sunset_timing" => true}})

      assert changeset.changes.config.errors[:min_sunset_time]
      assert changeset.changes.config.errors[:max_sunset_time]
      assert persisted(state)["override_sunset_timing"] == false

      assert {:ok, repaired} =
               Scenes.update_light_state(state.id, %{
                 config: %{"override_sunset_timing" => true, "min_sunset_time" => "17:00:00"}
               })

      assert persisted(repaired)["override_sunset_timing"] == true
    end

    test "does not excuse the other event's active window" do
      assert {:error, changeset} =
               Scenes.create_light_state(
                 "Mixed",
                 :circadian,
                 Map.merge(@inverted_sunset, %{
                   "override_sunrise_timing" => true,
                   "min_sunrise_time" => "09:00:00",
                   "max_sunrise_time" => "06:00:00"
                 })
               )

      assert changeset.changes.config.errors[:min_sunrise_time]
      refute changeset.changes.config.errors[:min_sunset_time]
    end

    test "still needs well-formed times" do
      assert {:error, changeset} =
               Scenes.create_light_state("Dormant", :circadian, %{"min_sunset_time" => "evening"})

      assert changeset.changes.config.errors[:min_sunset_time]
    end
  end
end
