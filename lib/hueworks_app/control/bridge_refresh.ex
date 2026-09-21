defmodule Hueworks.Control.BridgeRefresh do
  @moduledoc false

  alias Hueworks.Control.Bootstrap
  alias Hueworks.{Repo, RuntimeIO}
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Subscription

  def run(bridge_id) do
    if RuntimeIO.disabled?() do
      :disabled
    else
      refresh(Repo.get(Bridge, bridge_id))
    end
  end

  defp refresh(%Bridge{enabled: true} = bridge) do
    {stream, bootstrap} = modules(bridge.type)

    with :ok <- refresh_indexes(stream, bridge),
         :ok <- bootstrap.run(bridge) do
      :ok
    else
      {:error, :indexes} = error -> error
      _ -> {:error, :observations}
    end
  end

  defp refresh(_bridge), do: :skipped

  defp refresh_indexes(stream, bridge) do
    case Subscription.GenericEventStream.refresh(stream, bridge.id) do
      :ok -> :ok
      _ -> {:error, :indexes}
    end
  catch
    :exit, _ -> {:error, :indexes}
  end

  defp modules(:hue), do: {Subscription.HueEventStream, Bootstrap.Hue}
  defp modules(:ha), do: {Subscription.HomeAssistantEventStream, Bootstrap.HomeAssistant}
  defp modules(:z2m), do: {Subscription.Z2MEventStream, Bootstrap.Z2M}
  defp modules(:caseta), do: {Subscription.CasetaEventStream, Bootstrap.Caseta}
end
