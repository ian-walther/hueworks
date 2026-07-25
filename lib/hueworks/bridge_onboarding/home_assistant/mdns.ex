defmodule Hueworks.BridgeOnboarding.HomeAssistant.Mdns do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.HomeAssistant.Device
  alias Hueworks.BridgeOnboarding.Mdns

  @service ~c"_home-assistant._tcp.local"

  def discover(opts \\ []) do
    case Mdns.query(@service, 1_000, opts) do
      {:ok, response} -> {:ok, parse(response)}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse(response) do
    response
    |> Mdns.instances(@service)
    |> Enum.map(fn instance ->
      %Device{
        id: instance.txt["uuid"] || String.replace_suffix(instance.target, ".local", ""),
        host: instance.host || instance.target,
        port: instance.port,
        name: instance.txt["location_name"] || instance_name(instance.instance)
      }
      |> Device.normalize()
    end)
  end

  defp instance_name(instance) do
    instance
    |> String.replace_suffix("._home-assistant._tcp.local", "")
    |> String.trim()
    |> case do
      "" -> nil
      name -> name
    end
  end
end
