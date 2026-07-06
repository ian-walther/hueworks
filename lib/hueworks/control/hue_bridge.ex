defmodule Hueworks.Control.HueBridge do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias HueworksApp.Cache

  @cache_namespace :bridge_credentials
  @default_ttl_ms 10_000

  def credentials_for(%{bridge_id: bridge_id}) when is_integer(bridge_id) do
    Cache.get_or_load(
      @cache_namespace,
      {:hue, bridge_id},
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
        api_key = Bridge.credentials_struct(bridge).api_key

        if is_binary(api_key) and api_key != "" do
          {:ok, bridge.host, api_key}
        else
          {:error, :missing_api_key}
        end
    end
  end

  defp credentials_cache_ttl_ms do
    Application.get_env(:hueworks, :cache_bridge_credentials_ttl_ms, @default_ttl_ms)
  end
end
