defmodule Hueworks.Control.Z2MBridge do
  @moduledoc false

  alias Hueworks.Control.BridgeCredentialsCache
  alias Hueworks.Repo
  alias Hueworks.Control.Z2MConfig
  alias Hueworks.Schemas.Bridge

  def connection_for(entity) do
    bridge_id = if is_map(entity), do: Map.get(entity, :bridge_id)
    BridgeCredentialsCache.fetch(:z2m, bridge_id, fn -> load_connection(bridge_id) end)
  end

  defp load_connection(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      %Bridge{} = bridge ->
        {:ok, Z2MConfig.for_bridge(bridge)}
    end
  end
end
