defmodule Hueworks.HomeAssistant.AuthorizationTest do
  use ExUnit.Case, async: false

  alias Hueworks.HomeAssistant.Authorization
  alias Hueworks.Schemas.Bridge.Credentials

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

  test "builds an IndieAuth authorization URL from the canonical HueWorks URL" do
    assert {:ok, config} =
             Authorization.authorize(
               "https://ha.example.test",
               "http://hueworks.home",
               "one-use-state"
             )

    uri = URI.parse(config.url)
    query = URI.decode_query(uri.query)

    assert uri.scheme == "https"
    assert uri.host == "ha.example.test"
    assert uri.path == "/auth/authorize"
    assert query["response_type"] == "code"
    assert query["client_id"] == "http://hueworks.home"

    assert query["redirect_uri"] ==
             "http://hueworks.home/config/bridges/home-assistant/callback"

    assert query["state"] == "one-use-state"
  end

  test "rejects a callback origin that browsers cannot reach" do
    assert {:error, :invalid_callback_url} =
             Authorization.authorize("ha.local", "http://0.0.0.0:4000", "state")
  end

  test "exchanges an authorization code for refreshable credentials" do
    now = System.system_time(:second)

    respond(%{
      "access_token" => "short-lived",
      "expires_in" => 1800,
      "refresh_token" => "refresh-token",
      "token_type" => "Bearer"
    })

    assert {:ok, credentials} =
             Authorization.exchange_code(
               "ha.local",
               "http://hueworks.home",
               "authorization-code"
             )

    assert credentials == %{
             "access_token" => "short-lived",
             "auth_status" => "ready",
             "auth_type" => "oauth",
             "client_id" => "http://hueworks.home",
             "expires_at" => credentials["expires_at"],
             "refresh_token" => "refresh-token"
           }

    assert credentials["expires_at"] in (now + 1_799)..(now + 1_801)
  end

  test "refresh keeps the existing refresh token when Home Assistant omits it" do
    respond(%{"access_token" => "renewed", "expires_in" => 1800, "token_type" => "Bearer"})

    credentials = %Credentials{
      auth_type: "oauth",
      access_token: "expired",
      refresh_token: "refresh-token",
      expires_at: 1,
      client_id: "http://hueworks.home",
      auth_status: "ready"
    }

    assert {:ok, refreshed} = Authorization.refresh("ha.local", credentials)
    assert refreshed["access_token"] == "renewed"
    assert refreshed["refresh_token"] == "refresh-token"
    assert refreshed["auth_status"] == "ready"
  end

  test "a rejected refresh requires reauthorization without leaking response credentials" do
    Application.put_env(
      :hueworks,
      :home_assistant_auth_http_response,
      {:ok,
       %HTTPoison.Response{
         status_code: 400,
         body: Jason.encode!(%{"error" => "invalid_grant", "refresh_token" => "secret"})
       }}
    )

    credentials = %Credentials{
      auth_type: "oauth",
      refresh_token: "refresh-token",
      client_id: "http://hueworks.home"
    }

    assert {:error, :reauthorization_required} =
             Authorization.refresh("ha.local", credentials)
  end

  defmodule HTTPClient do
    def post(url, body, headers, opts) do
      if listener = Process.whereis(:home_assistant_authorization_test_listener) do
        send(listener, {:auth_http_post, url, body, headers, opts})
      end

      Application.fetch_env!(:hueworks, :home_assistant_auth_http_response)
    end
  end

  defp respond(payload) do
    Application.put_env(
      :hueworks,
      :home_assistant_auth_http_response,
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(payload)}}
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:hueworks, key)
  defp restore_env(key, value), do: Application.put_env(:hueworks, key, value)
end
