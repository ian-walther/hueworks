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
    do: build_command(light.source_id, "GoToLevel", %{"Level" => 100})

  defp power_payload(light, :off),
    do: build_command(light.source_id, "GoToLevel", %{"Level" => 0})

  defp brightness_payload(light, level) do
    if supports_level?(light) do
      build_command(light.source_id, "GoToLevel", %{"Level" => Util.clamp(round(level), 0, 100)})
    else
      if level <= 0 do
        power_payload(light, :off)
      else
        power_payload(light, :on)
      end
    end
  end

  defp build_command(zone_id, command_type, params) do
    %{
      "CommuniqueType" => "CreateRequest",
      "Header" => %{
        "Url" => "/zone/#{zone_id}/commandprocessor",
        "ClientTag" => "hueworks"
      },
      "Body" => %{
        "Command" => %{
          "CommandType" => command_type,
          "Parameter" => [%{"Type" => "Level", "Value" => params["Level"]}]
        }
      }
    }
  end

  defp supports_level?(%{metadata: %{"type" => type}}) when is_binary(type) do
    not String.contains?(String.downcase(type), "switch")
  end

  defp supports_level?(_light), do: true
end
