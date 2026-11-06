defmodule Hueworks.Control.CasetaPayload do
  @moduledoc false

  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Control.Transition
  alias Hueworks.Util

  # Color-tuning devices use different LEAP commands.
  @fade_dimmer_types ~w(
    WallDimmer PlugInDimmer InLineDimmer SunnataDimmer TempInWallPaddleDimmer
    WallDimmerWithPreset Dimmed DivaSmartDimmer PowPak0-10V
  )

  def action_payload({:set_state, desired}, light, opts) when is_map(desired) do
    case target_level(light, desired) do
      nil ->
        :ignore

      level ->
        seconds = fade_seconds(light, opts)
        {zone_payload(light.source_id, level_command(level, seconds)), seconds * 1_000}
    end
  end

  def action_payload(_action, _light, _opts), do: :ignore

  defp target_level(light, desired) do
    power = LightStateSemantics.power_value(desired)
    brightness = LightStateSemantics.brightness_value(desired)

    cond do
      power == :off -> 0
      not is_nil(brightness) -> brightness_level(light, brightness)
      power == :on -> 100
      true -> nil
    end
  end

  defp brightness_level(light, level) do
    cond do
      supports_level?(light) -> level |> round() |> Util.clamp(0, 100)
      level <= 0 -> 0
      true -> 100
    end
  end

  defp fade_seconds(%{metadata: %{"type" => type}}, opts) when type in @fade_dimmer_types do
    case Transition.transition_ms(opts) do
      nil -> 0
      duration_ms -> max(1, div(duration_ms + 500, 1_000))
    end
  end

  defp fade_seconds(_light, _opts), do: 0

  defp level_command(level, 0) do
    %{"CommandType" => "GoToLevel", "Parameter" => [%{"Type" => "Level", "Value" => level}]}
  end

  defp level_command(level, seconds) do
    %{
      "CommandType" => "GoToDimmedLevel",
      "DimmedLevelParameters" => %{"Level" => level, "FadeTime" => format_duration(seconds)}
    }
  end

  defp format_duration(seconds) do
    [div(seconds, 3_600), rem(div(seconds, 60), 60), rem(seconds, 60)]
    |> Enum.map_join(":", fn part -> part |> Integer.to_string() |> String.pad_leading(2, "0") end)
  end

  defp zone_payload(zone_id, command) do
    %{
      "CommuniqueType" => "CreateRequest",
      "Header" => %{
        "Url" => "/zone/#{zone_id}/commandprocessor",
        "ClientTag" => "hueworks"
      },
      "Body" => %{"Command" => command}
    }
  end

  defp supports_level?(%{metadata: %{"type" => type}}) when is_binary(type) do
    not String.contains?(String.downcase(type), "switch")
  end

  defp supports_level?(_light), do: true
end
