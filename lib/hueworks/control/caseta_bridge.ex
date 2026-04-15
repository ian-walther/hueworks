defmodule Hueworks.Control.CasetaBridge do
  @moduledoc false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  def connection_for(%{bridge_id: bridge_id}) when is_integer(bridge_id) do
    case Repo.get(Bridge, bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        credentials = Bridge.credentials_struct(bridge)
        cert_path = credentials.cert_path
        key_path = credentials.key_path
        cacert_path = credentials.cacert_path

        if Enum.any?([cert_path, key_path, cacert_path], &invalid_credential?/1) do
          {:error, :missing_credentials}
        else
          {:ok, bridge.host,
           [
             certfile: cert_path,
             keyfile: key_path,
             cacertfile: cacert_path,
             verify: :verify_none,
             versions: [:"tlsv1.2"]
           ]}
        end
    end
  end

  def connection_for(_entity), do: {:error, :missing_bridge_id}

  defp invalid_credential?(value) do
    not is_binary(value) or value == "" or value == "CHANGE_ME"
  end
end
