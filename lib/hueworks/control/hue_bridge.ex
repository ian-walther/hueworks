defmodule Hueworks.Control.HueBridge do
  @moduledoc false

  alias Hueworks.Control.BridgeCredentialsCache
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def credentials_for(entity) do
    bridge_id = if is_map(entity), do: Map.get(entity, :bridge_id)
    BridgeCredentialsCache.fetch(:hue, bridge_id, fn -> load_credentials(bridge_id) end)
  end

  defp load_credentials(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        api_key = Bridge.credentials_struct(bridge).api_key

        if is_binary(api_key) and api_key != "" do
          {:ok, bridge.host, api_key}
        else
          {:error, :missing_api_key}
        end
    end
  end
end
