defmodule Hueworks.Control.HomeAssistantBridgeTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.HomeAssistantBridge
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Light}

  setup do
    previous_client = Application.get_env(:hueworks, :home_assistant_auth_http_client)
    previous_response = Application.get_env(:hueworks, :home_assistant_auth_http_response)

    Application.put_env(
      :hueworks,
      :home_assistant_auth_http_client,
      __MODULE__.HTTPClient
    )

    on_exit(fn ->
      restore_env(:home_assistant_auth_http_client, previous_client)
      restore_env(:home_assistant_auth_http_response, previous_response)
    end)

    :ok
  end

  test "legacy credentials return a normalized HTTP base URL" do
    {_bridge, light} = insert_entity!("https://ha.example.test", %{"token" => "long-lived"})

    assert HomeAssistantBridge.credentials_for(light) ==
             {:ok, "https://ha.example.test", "long-lived"}
  end

  test "an unauthorized request refreshes OAuth credentials and retries once" do
    Application.put_env(
      :hueworks,
      :home_assistant_auth_http_response,
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           Jason.encode!(%{
             "access_token" => "renewed",
             "expires_in" => 1800,
             "token_type" => "Bearer"
           })
       }}
    )

    {_bridge, light} =
      insert_entity!("ha.local:8123", %{
        "auth_type" => "oauth",
        "access_token" => "rejected",
        "refresh_token" => "refresh-token",
        "expires_at" => System.system_time(:second) + 1800,
        "client_id" => "http://hueworks.home",
        "auth_status" => "ready"
      })

    {:ok, calls} = Agent.start_link(fn -> [] end)

    request = fn host, token ->
      Agent.update(calls, &[{host, token} | &1])

      case token do
        "rejected" -> {:error, {:http_error, 401, "unauthorized"}}
        "renewed" -> {:ok, :ok}
      end
    end

    assert {:ok, :ok} = HomeAssistantBridge.request(light, request)

    assert Agent.get(calls, &Enum.reverse/1) == [
             {"http://ha.local:8123", "rejected"},
             {"http://ha.local:8123", "renewed"}
           ]
  end

  defmodule HTTPClient do
    def post(_url, _body, _headers, _opts) do
      Application.fetch_env!(:hueworks, :home_assistant_auth_http_response)
    end
  end

  defp insert_entity!(host, credentials) do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: host,
        credentials: credentials
      })
      |> Repo.insert!()

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :ha,
        source_id: "light.lamp",
        bridge_id: bridge.id
      })

    {bridge, light}
  end

  defp restore_env(key, nil), do: Application.delete_env(:hueworks, key)
  defp restore_env(key, value), do: Application.put_env(:hueworks, key, value)
end
