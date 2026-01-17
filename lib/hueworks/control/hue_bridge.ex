defmodule Hueworks.Control.HueBridge do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def credentials_for(entity) do
    case bridge_host(entity) do
      nil ->
        {:error, :missing_bridge_host}

      host ->
        case Repo.get_by(Bridge, type: :hue, host: host) do
          nil ->
            {:error, :bridge_not_found}

          bridge ->
            api_key = bridge.credentials["api_key"]

            if is_binary(api_key) and api_key != "" do
              {:ok, host, api_key}
            else
              {:error, :missing_api_key}
            end
        end
    end
  end

  defp bridge_host(%{metadata: metadata}) when is_map(metadata) do
    metadata["bridge_host"]
  end

  defp bridge_host(_entity), do: nil
end
