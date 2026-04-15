defmodule Hueworks.Control.HueBridge do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias HueworksApp.Cache

  @cache_namespace :bridge_credentials
  @default_ttl_ms 10_000

  def credentials_for(entity) do
    case bridge_host(entity) do
      nil ->
        {:error, :missing_bridge_host}

      host ->
        Cache.get_or_load(
          @cache_namespace,
          {:hue, host},
          fn -> load_credentials(host) end,
          ttl_ms: credentials_cache_ttl_ms()
        )
    end
  end

  defp bridge_host(%{metadata: metadata}) when is_map(metadata) do
    metadata["bridge_host"]
  end

  defp bridge_host(_entity), do: nil

  defp load_credentials(host) do
    case Repo.get_by(Bridge, type: :hue, host: host) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        api_key = Bridge.credentials_struct(bridge).api_key

        if is_binary(api_key) and api_key != "" do
          {:ok, host, api_key}
        else
          {:error, :missing_api_key}
        end
    end
  end

  defp credentials_cache_ttl_ms do
    Application.get_env(:hueworks, :cache_bridge_credentials_ttl_ms, @default_ttl_ms)
  end
end
