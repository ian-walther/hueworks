defmodule Hueworks.Control.CasetaPayload do
  @moduledoc false

  alias Hueworks.Util

  def action_payload(:on, light) do
    build_command(light.source_id, "GoToLevel", %{"Level" => 100})
  end

  def action_payload(:off, light) do
    build_command(light.source_id, "GoToLevel", %{"Level" => 0})
  end

  def action_payload({:set_state, desired}, light) when is_map(desired) do
    power = Map.get(desired, :power) || Map.get(desired, "power")
    brightness = Map.get(desired, :brightness) || Map.get(desired, "brightness")

    cond do
      power in [:off, "off"] ->
        action_payload(:off, light)

      not is_nil(brightness) ->
        action_payload({:brightness, brightness}, light)

      power in [:on, "on"] ->
        action_payload(:on, light)

      true ->
        :ignore
    end
  end

  def action_payload({:brightness, level}, light) do
    if supports_level?(light) do
      build_command(light.source_id, "GoToLevel", %{"Level" => Util.clamp(round(level), 0, 100)})
    else
      if level <= 0 do
        action_payload(:off, light)
      else
        action_payload(:on, light)
      end
    end
  end

  def action_payload(_action, _light), do: :ignore

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
