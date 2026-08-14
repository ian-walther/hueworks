defmodule Hueworks.Control.BridgeCredentialsCache do
  @moduledoc false

  alias HueworksApp.Cache

  @cache_namespace :bridge_credentials
  @default_ttl_ms 10_000

  def fetch(source, bridge_id, loader)
      when is_atom(source) and is_integer(bridge_id) and is_function(loader, 0) do
    Cache.get_or_load(
      @cache_namespace,
      {source, bridge_id},
      loader,
      ttl_ms: credentials_cache_ttl_ms()
    )
  end

  def fetch(_source, _bridge_id, _loader), do: {:error, :missing_bridge_id}

  def invalidate(source, bridge_id) when is_atom(source) and is_integer(bridge_id) do
    Cache.delete(@cache_namespace, {source, bridge_id})
  end

  defp credentials_cache_ttl_ms do
    Application.get_env(:hueworks, :cache_bridge_credentials_ttl_ms, @default_ttl_ms)
  end
end
