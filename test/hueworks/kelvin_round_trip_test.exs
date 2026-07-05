defmodule Hueworks.KelvinRoundTripTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.{HomeAssistantPayload, StateParser, Z2MPayload}
  alias Hueworks.Kelvin

  @profiles [
    %{
      name: "default extended profile",
      source_id: "light.default_extended",
      extended_kelvin_range: true,
      extended_min_kelvin: 2000,
      actual_min_kelvin: 2700,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2000,
      reported_max_kelvin: 6329
    },
    %{
      name: "custom extended profile",
      source_id: "light.custom_extended",
      extended_kelvin_range: true,
      extended_min_kelvin: 1800,
      actual_min_kelvin: 3000,
      actual_max_kelvin: 6500,
      reported_min_kelvin: 2200,
      reported_max_kelvin: 6500
    }
  ]

  test "HA control payloads round-trip through simulated reports across extended profiles" do
    check_profiles(&ha_round_trip/2)
  end

  test "Z2M control payloads round-trip through simulated reports across extended profiles" do
    check_profiles(&z2m_round_trip/2)
  end

  defp check_profiles(round_trip) do
    Enum.each(@profiles, fn profile ->
      Enum.each(sample_kelvins(profile), fn requested ->
        reported_values = round_trip.(profile, requested) |> List.wrap()

        Enum.each(reported_values, fn reported ->
          assert Kelvin.equivalent_temperature?(reported, requested, mired_tolerance: 1),
                 "#{profile.name} failed at #{requested}K: parsed #{reported}K"
        end)
      end)
    end)
  end

  defp sample_kelvins(profile) do
    low = profile.extended_min_kelvin
    boundary = profile.actual_min_kelvin
    high = profile.actual_max_kelvin

    [
      low,
      low + 1,
      div(low + boundary, 2),
      boundary - 100,
      boundary - 1,
      boundary,
      boundary + 1,
      boundary + 25,
      div(boundary + high, 2),
      high - 1,
      high
    ]
    |> Enum.uniq()
  end

  defp ha_round_trip(profile, requested) do
    assert {"turn_on", payload} =
             HomeAssistantPayload.action_payload({:set_state, %{kelvin: requested}}, profile)

    reports =
      case payload do
        %{"xy_color" => xy} ->
          [
            %{
              "color_mode" => "xy",
              "xy_color" => xy,
              "color_temp_kelvin" => profile.reported_min_kelvin
            }
          ]

        %{"color_temp_kelvin" => kelvin} ->
          [
            %{"color_mode" => "color_temp", "color_temp_kelvin" => kelvin},
            %{"color_mode" => "color_temp", "color_temp" => 1_000_000 / kelvin}
          ]
      end

    Enum.map(reports, fn attrs ->
      StateParser.home_assistant_state(%{"state" => "on", "attributes" => attrs}, profile).kelvin
    end)
  end

  defp z2m_round_trip(profile, requested) do
    payload = Z2MPayload.action_payload({:set_state, %{kelvin: requested}}, profile)

    reports =
      case payload do
        %{"color" => color} ->
          [
            %{
              "state" => "ON",
              "color_mode" => "xy",
              "color" => color,
              "color_temp" => round(1_000_000 / profile.reported_min_kelvin)
            }
          ]

        %{"color_temp" => mired} ->
          [
            %{"state" => "ON", "color_mode" => "color_temp", "color_temp" => mired},
            %{
              "state" => "ON",
              "color_mode" => "color_temp",
              "color_temp_kelvin" => round(1_000_000 / mired)
            }
          ]
      end

    Enum.map(reports, fn report -> StateParser.z2m_state(report, profile).kelvin end)
  end
end
