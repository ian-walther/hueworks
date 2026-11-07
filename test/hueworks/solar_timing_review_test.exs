defmodule Hueworks.SolarTimingReviewTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.AppSettings
  alias Hueworks.Circadian
  alias Hueworks.Schemas.AppSetting
  alias Phoenix.PubSub

  @solar %{latitude: 40.7128, longitude: -74.0060, timezone: "America/New_York"}

  setup do
    {:ok, _settings} = AppSettings.upsert_global(@solar)
    :ok
  end

  test "a surrounding transaction cannot leak uncommitted settings into reads" do
    {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               assert {:error, :nested_settings_transaction} =
                        AppSettings.upsert_global(%{min_sunset_time: "19:00"})

               Repo.rollback(:cancelled)
             end)

    persisted = Repo.get_by!(AppSetting, scope: "global")
    assert persisted.min_sunset_time == "18:00:00"
    assert AppSettings.get_global().min_sunset_time == persisted.min_sunset_time
  end

  test "a refused settings edit cannot announce a committed change" do
    PubSub.subscribe(Hueworks.PubSub, "domain_events")

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               assert {:error, :nested_settings_transaction} =
                        AppSettings.upsert_global(%{min_sunset_time: "19:00"})

               Repo.rollback(:cancelled)
             end)

    refute_receive {:global_settings_changed, _fields}, 50
  end

  test "inherited timing ignores a dormant local window even if its bounds are inverted" do
    inherited = %{
      "override_sunrise_timing" => false,
      "override_sunset_timing" => false
    }

    dormant =
      Map.merge(inherited, %{
        "min_sunrise_time" => "09:00:00",
        "max_sunrise_time" => "06:00:00",
        "min_sunset_time" => "21:00:00",
        "max_sunset_time" => "18:00:00"
      })

    now = ~U[2026-12-21 22:00:00Z]
    solar = Map.put(@solar, :min_sunset_time, "18:00:00")

    assert {:ok, expected} = Circadian.calculate(inherited, solar, now)
    assert Circadian.calculate(dormant, solar, now) == {:ok, expected}
  end

  for value <- ["18:00:00.5", "18:00:00+05:00", "18:00:00Z", "T18:00:00", "18:00:60", "7:30"] do
    test "global bounds reject #{value} rather than publishing an incompatible time" do
      {:ok, _settings} = AppSettings.upsert_global(%{min_sunset_time: "18:00"})

      assert {:error, changeset} = AppSettings.upsert_global(%{min_sunset_time: unquote(value)})
      assert changeset.errors[:min_sunset_time]
      assert AppSettings.get_global().min_sunset_time == "18:00:00"
    end
  end
end
