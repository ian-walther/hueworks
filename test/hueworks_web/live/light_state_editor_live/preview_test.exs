defmodule HueworksWeb.LightStateEditorLive.PreviewTest do
  use ExUnit.Case, async: true

  alias Hueworks.CircadianPreview
  alias HueworksWeb.LightStateEditorLive.Preview

  test "refresh_assigns surfaces preview input errors cleanly" do
    assert %{
             circadian_preview: nil,
             circadian_preview_error: "Preview needs a latitude."
           } =
             Preview.refresh_assigns(
               :circadian,
               %{},
               "2026-03-08",
               "",
               "-74.0060",
               "America/New_York"
             )
  end

  test "chart helpers format sampled preview data" do
    {:ok, preview} =
      CircadianPreview.sample_day(
        %{},
        %{
          latitude: "40.7128",
          longitude: "-74.0060",
          timezone: "America/New_York"
        },
        "2026-03-08",
        interval_minutes: 120
      )

    assert Preview.chart_path(preview, :brightness) =~ "M "

    points = Preview.chart_points_json(preview, :brightness) |> Jason.decode!()

    assert hd(points)["time_label"] == "00:00"
    assert hd(points)["value_label"] =~ "%"
    assert Preview.marker_summary(preview, :sunrise) =~ ":"
    assert Preview.range_label(preview, :kelvin) =~ "K - "
    assert Preview.time_input_value("06:30") == "06:30:00"
  end

  test "refresh_assigns passes global bounds to the shared calculation" do
    assert %{circadian_preview: preview, circadian_preview_error: nil} =
             Preview.refresh_assigns(
               :circadian,
               %{"override_sunset_timing" => false},
               "2026-12-21",
               "47.6062",
               "-122.3321",
               "America/Los_Angeles",
               %{min_sunset_time: "18:00:00"}
             )

    assert Preview.marker_summary(preview, :sunset) == "18:00"
  end

  test "error messages explain seasonal failures and ordering conflicts" do
    assert Preview.error_message({:sun_event_unavailable, :sunset, ~D[2026-06-21]}) ==
             "Preview unavailable: no astronomical sunset at this latitude on 2026-06-21."

    assert Preview.error_message({:invalid_sun_event_order, [:sunset, :sunrise]}) ==
             "Preview unavailable: sunrise and sunset are out of order for this date."
  end
end
