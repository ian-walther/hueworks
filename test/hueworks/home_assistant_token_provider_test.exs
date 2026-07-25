defmodule Hueworks.HomeAssistant.TokenProviderTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.HomeAssistant.TokenProvider
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  setup do
    previous_client = Application.get_env(:hueworks, :home_assistant_auth_http_client)
    previous_counter = Application.get_env(:hueworks, :home_assistant_auth_refresh_counter)
    previous_response = Application.get_env(:hueworks, :home_assistant_auth_http_response)

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Application.put_env(
      :hueworks,
      :home_assistant_auth_http_client,
      __MODULE__.HTTPClient
    )

    Application.put_env(:hueworks, :home_assistant_auth_refresh_counter, counter)

    server = Module.concat(__MODULE__, "Server#{System.unique_integer([:positive])}")
    start_supervised!({TokenProvider, name: server})

    on_exit(fn ->
      restore_env(:home_assistant_auth_http_client, previous_client)
      restore_env(:home_assistant_auth_refresh_counter, previous_counter)
      restore_env(:home_assistant_auth_http_response, previous_response)
    end)

    {:ok, server: server, counter: counter}
  end

  test "legacy long-lived tokens remain available without refresh", %{
    server: server,
    counter: counter
  } do
    bridge = insert_ha_bridge!(%{"token" => "long-lived"})

    assert {:ok, "long-lived"} = TokenProvider.token_for(bridge.id, server)
    assert Agent.get(counter, & &1) == 0
  end

  test "a current OAuth access token is reused without a refresh", %{
    server: server,
    counter: counter
  } do
    bridge =
      insert_ha_bridge!(
        expired_oauth_credentials()
        |> Map.put("access_token", "still-current")
        |> Map.put("expires_at", System.system_time(:second) + 1800)
      )

    assert {:ok, "still-current"} = TokenProvider.token_for(bridge, server)
    assert Agent.get(counter, & &1) == 0
  end

  test "concurrent callers cause one refresh and share the persisted token", %{
    server: server,
    counter: counter
  } do
    respond(200, %{"access_token" => "renewed", "expires_in" => 1800, "token_type" => "Bearer"})
    bridge = insert_ha_bridge!(expired_oauth_credentials())

    results =
      1..8
      |> Enum.map(fn _ -> Task.async(fn -> TokenProvider.token_for(bridge, server) end) end)
      |> Task.await_many()

    assert Enum.uniq(results) == [{:ok, "renewed"}]
    assert Agent.get(counter, & &1) == 1
    assert Bridge.credentials_struct(Repo.get!(Bridge, bridge.id)).access_token == "renewed"
  end

  test "a permanently rejected refresh is persisted as requiring reauthorization", %{
    server: server
  } do
    respond(400, %{"error" => "invalid_grant"})
    bridge = insert_ha_bridge!(expired_oauth_credentials())

    assert {:error, :reauthorization_required} = TokenProvider.token_for(bridge.id, server)

    credentials = bridge.id |> then(&Repo.get!(Bridge, &1)) |> Bridge.credentials_struct()
    assert credentials.auth_status == "reauthorization_required"
    assert credentials.refresh_token == "refresh-token"
  end

  test "a transient refresh failure leaves the credential eligible for retry", %{server: server} do
    Application.put_env(
      :hueworks,
      :home_assistant_auth_http_response,
      {:error, %HTTPoison.Error{reason: :econnrefused}}
    )

    bridge = insert_ha_bridge!(expired_oauth_credentials())

    assert {:error, :temporarily_unavailable} = TokenProvider.token_for(bridge.id, server)
    assert Bridge.credentials_struct(Repo.get!(Bridge, bridge.id)).auth_status == "ready"
  end

  defmodule HTTPClient do
    def post(_url, _body, _headers, _opts) do
      counter = Application.fetch_env!(:hueworks, :home_assistant_auth_refresh_counter)
      Agent.update(counter, &(&1 + 1))
      Application.fetch_env!(:hueworks, :home_assistant_auth_http_response)
    end
  end

  defp insert_ha_bridge!(credentials) do
    %Bridge{}
    |> Bridge.changeset(%{
      type: :ha,
      name: "Home Assistant",
      host: "ha.local:8123",
      credentials: credentials
    })
    |> Repo.insert!()
  end

  defp expired_oauth_credentials do
    %{
      "auth_type" => "oauth",
      "access_token" => "expired",
      "refresh_token" => "refresh-token",
      "expires_at" => 1,
      "client_id" => "http://hueworks.home",
      "auth_status" => "ready"
    }
  end

  defp respond(status, payload) do
    Application.put_env(
      :hueworks,
      :home_assistant_auth_http_response,
      {:ok, %HTTPoison.Response{status_code: status, body: Jason.encode!(payload)}}
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:hueworks, key)
  defp restore_env(key, value), do: Application.put_env(:hueworks, key, value)
end
