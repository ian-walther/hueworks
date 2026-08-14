defmodule Hueworks.Control.CasetaPayload do
  @moduledoc false

  alias Hueworks.Control.LightStateSemantics
  alias Hueworks.Util

  def action_payload({:set_state, desired}, light) when is_map(desired) do
    power = LightStateSemantics.power_value(desired)
    brightness = LightStateSemantics.brightness_value(desired)

    cond do
      power == :off ->
        power_payload(light, :off)

      not is_nil(brightness) ->
        brightness_payload(light, brightness)

      power == :on ->
        power_payload(light, :on)

      true ->
        :ignore
    end
  end

  def action_payload(_action, _light), do: :ignore

  defp power_payload(light, :on),
    do: go_to_level_command(light.source_id, 100)

  defp power_payload(light, :off),
    do: go_to_level_command(light.source_id, 0)

  defp brightness_payload(light, level) do
    if supports_level?(light) do
      go_to_level_command(light.source_id, Util.clamp(round(level), 0, 100))
    else
      if level <= 0 do
        power_payload(light, :off)
      else
        power_payload(light, :on)
      end
    end
  end

  defp go_to_level_command(zone_id, level) do
    %{
      "CommuniqueType" => "CreateRequest",
      "Header" => %{
        "Url" => "/zone/#{zone_id}/commandprocessor",
        "ClientTag" => "hueworks"
      },
      "Body" => %{
        "Command" => %{
          "CommandType" => "GoToLevel",
          "Parameter" => [%{"Type" => "Level", "Value" => level}]
        }
      }
    }
  end

  defp supports_level?(%{metadata: %{"type" => type}}) when is_binary(type) do
    not String.contains?(String.downcase(type), "switch")
  end

  defp supports_level?(_light), do: true
end
