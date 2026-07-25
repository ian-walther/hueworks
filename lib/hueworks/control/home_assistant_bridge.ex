defmodule Hueworks.Control.HomeAssistantBridge do
  @moduledoc false

  alias Hueworks.HomeAssistant.Host
  alias Hueworks.HomeAssistant.TokenProvider
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias HueworksApp.Cache

  @cache_namespace :bridge_credentials
  @default_ttl_ms 10_000

  def credentials_for(%{bridge_id: bridge_id}) when is_integer(bridge_id) do
    Cache.get_or_load(
      @cache_namespace,
      {:ha, bridge_id},
      fn -> load_credentials(bridge_id) end,
      ttl_ms: credentials_cache_ttl_ms()
    )
  end

  def credentials_for(_entity), do: {:error, :missing_bridge_id}

  def request(%{bridge_id: bridge_id} = entity, request_fun)
      when is_integer(bridge_id) and is_function(request_fun, 2) do
    with {:ok, host, token} <- credentials_for(entity) do
      case request_fun.(host, token) do
        result when result in [{:error, :unauthorized}, {:error, {:http_error, 401}}] ->
          retry_with_refreshed_token(bridge_id, request_fun)

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
    Cache.delete(@cache_namespace, {:ha, bridge_id})

    with bridge when not is_nil(bridge) <- Repo.get(Bridge, bridge_id),
         {:ok, token} <- TokenProvider.refresh(bridge.id) do
      request_fun.(Host.base_url(bridge.host), token)
    else
      nil -> {:error, :bridge_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp credentials_cache_ttl_ms do
    Application.get_env(:hueworks, :cache_bridge_credentials_ttl_ms, @default_ttl_ms)
  end
end
