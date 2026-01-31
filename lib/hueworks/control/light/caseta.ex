defmodule Hueworks.Control.Light.Caseta do
  @moduledoc false

  alias Hueworks.Control.{CasetaBridge, CasetaClient}
  alias Hueworks.Util

  def handle(light, action) do
    with {:ok, host, ssl_opts} <- CasetaBridge.connection_for(light),
         payload <- action_payload(action, light),
         :ok <- CasetaClient.request(host, ssl_opts, payload) do
      :ok
    else
      {:error, _} = error -> error
      :ignore -> :ok
    end
  end

  defp action_payload(:on, light) do
    build_command(light.source_id, "GoToLevel", %{"Level" => 100})
  end

  defp action_payload(:off, light) do
    build_command(light.source_id, "GoToLevel", %{"Level" => 0})
  end

  defp action_payload({:brightness, level}, light) do
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

  defp action_payload(_action, _light), do: :ignore

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
