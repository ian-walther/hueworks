defmodule Hueworks.Control.HomeAssistantBridge do
  @moduledoc false

  alias Hueworks.Control.BridgeCredentialsCache
  alias Hueworks.HomeAssistant.Host
  alias Hueworks.HomeAssistant.TokenProvider
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def credentials_for(entity) do
    bridge_id = if is_map(entity), do: Map.get(entity, :bridge_id)
    BridgeCredentialsCache.fetch(:ha, bridge_id, fn -> load_credentials(bridge_id) end)
  end

  def request(%{bridge_id: bridge_id} = entity, request_fun)
      when is_integer(bridge_id) and is_function(request_fun, 2) do
    with {:ok, host, token} <- credentials_for(entity) do
      case request_fun.(host, token) do
        {:error, {:http_error, 401, _body}} ->
          retry_with_refreshed_token(bridge_id, request_fun)

        result ->
          result
      end
    end
  end

  def request(_entity, _request_fun), do: {:error, :missing_bridge_id}

  defp load_credentials(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        case TokenProvider.token_for(bridge.id) do
          {:ok, token} -> {:ok, Host.base_url(bridge.host), token}
          {:error, _reason} = error -> error
        end
    end
  end

  defp retry_with_refreshed_token(bridge_id, request_fun) do
    BridgeCredentialsCache.invalidate(:ha, bridge_id)

    with bridge when not is_nil(bridge) <- Repo.get(Bridge, bridge_id),
         {:ok, token} <- TokenProvider.refresh(bridge.id) do
      request_fun.(Host.base_url(bridge.host), token)
    else
      nil -> {:error, :bridge_not_found}
      {:error, _reason} = error -> error
    end
  end
end
