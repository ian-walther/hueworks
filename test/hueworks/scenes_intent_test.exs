defmodule Hueworks.ScenesIntentTest do
  use ExUnit.Case, async: true

  alias Hueworks.Scenes.Intent.{BuildOptions, DesiredAttrs}

  test "build options returns a typed runtime struct" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert %BuildOptions{
             occupied: true,
             now: ^now,
             target_light_ids: target_light_ids,
             circadian_only: true,
             power_overrides: %{1 => :off},
             preserve_power_latches: false
           } =
             BuildOptions.from_opts(
               occupied: true,
               now: now,
               target_light_ids: [1, 2, 2],
               circadian_only: true,
               power_overrides: %{1 => :off},
               preserve_power_latches: false
             )

    assert target_light_ids == MapSet.new([1, 2])
  end

  test "build options accepts an existing struct unchanged" do
    opts = %BuildOptions{
      occupied: false,
      now: DateTime.utc_now(),
      target_light_ids: MapSet.new(),
      circadian_only: false,
      power_overrides: %{},
      preserve_power_latches: true
    }

    assert BuildOptions.from_opts(opts) == opts
  end

  test "desired attrs drops nil values when converted to a map" do
    assert %{power: :on, brightness: 40, x: 0.1, y: 0.2} =
             %DesiredAttrs{power: :on, brightness: 40, x: 0.1, y: 0.2}
             |> DesiredAttrs.to_map()
  end
end
