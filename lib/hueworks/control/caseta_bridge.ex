defmodule Hueworks.Control.CasetaBridge do
  @moduledoc false

  alias Hueworks.Control.CasetaLeap
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias HueworksApp.Cache

  @cache_namespace :bridge_credentials
  @default_ttl_ms 10_000

  def connection_for(%{bridge_id: bridge_id}) when is_integer(bridge_id) do
    Cache.get_or_load(
      @cache_namespace,
      {:caseta, bridge_id},
      fn -> load_connection(bridge_id) end,
      ttl_ms: credentials_cache_ttl_ms()
    )
  end

  def connection_for(_entity), do: {:error, :missing_bridge_id}

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

  defp credentials_cache_ttl_ms do
    Application.get_env(:hueworks, :cache_bridge_credentials_ttl_ms, @default_ttl_ms)
  end
end
