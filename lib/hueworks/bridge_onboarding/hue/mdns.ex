defmodule Hueworks.BridgeOnboarding.Hue.Mdns do
  @moduledoc false

  alias Hueworks.BridgeOnboarding.Hue.Device
  alias Hueworks.BridgeOnboarding.Mdns

  @service ~c"_hue._tcp.local"

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
        id: instance.txt["bridgeid"] || instance.txt["id"],
        host: instance.host || instance.target,
        name: instance.txt["name"] || instance_name(instance.instance),
        sources: [:mdns]
      }
    end)
  end

  defp instance_name(instance) do
    instance
    |> String.replace_suffix("._hue._tcp.local", "")
    |> String.trim()
    |> case do
      "" -> nil
      name -> name
    end
  end
end
