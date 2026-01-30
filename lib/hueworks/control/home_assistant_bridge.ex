defmodule Hueworks.Control.HomeAssistantBridge do
  @moduledoc false

  alias Hueworks.HomeAssistant.Host
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def credentials_for(%{bridge_id: bridge_id}) when is_integer(bridge_id) do
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

  def credentials_for(_entity), do: {:error, :missing_bridge_id}

 
end
