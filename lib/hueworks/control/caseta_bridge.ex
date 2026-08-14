defmodule Hueworks.Control.CasetaBridge do
  @moduledoc false

  alias Hueworks.Control.BridgeCredentialsCache
  alias Hueworks.Control.CasetaLeap
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def connection_for(entity) do
    bridge_id = if is_map(entity), do: Map.get(entity, :bridge_id)
    BridgeCredentialsCache.fetch(:caseta, bridge_id, fn -> load_connection(bridge_id) end)
  end

  defp load_connection(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        case CasetaLeap.ssl_opts_for(bridge) do
          {:ok, ssl_opts} -> {:ok, bridge.host, ssl_opts}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
