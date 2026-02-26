defmodule Hueworks.Control.HomeAssistantBridge do
  @moduledoc false

  alias Hueworks.HomeAssistant.Host
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

  defp load_credentials(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        token = bridge.credentials["token"]

        if is_binary(token) and token != "" do
          {:ok, Host.normalize(bridge.host), token}
        else
          {:error, :missing_token}
        end
    end
  end

  defp credentials_cache_ttl_ms do
    Application.get_env(:hueworks, :cache_bridge_credentials_ttl_ms, @default_ttl_ms)
  end
end
