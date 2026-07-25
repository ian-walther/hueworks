defmodule HueworksWeb.HomeAssistantAuthControllerTest do
  use HueworksWeb.ConnCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  @authorize_path "/config/bridges/home-assistant/authorize"
  @callback_path "/config/bridges/home-assistant/callback"

  setup do
    previous_authorization =
      Application.get_env(:hueworks, :home_assistant_authorization_module)

    previous_validator =
      Application.get_env(:hueworks, :home_assistant_connection_validator_module)

    previous_exchange = Application.get_env(:hueworks, :home_assistant_test_exchange)
    previous_validation = Application.get_env(:hueworks, :home_assistant_test_validation)
    previous_ttl = Application.get_env(:hueworks, :home_assistant_authorization_state_ttl_seconds)

    Application.put_env(
      :hueworks,
      :home_assistant_authorization_module,
      __MODULE__.Authorization
    )

    Application.put_env(
      :hueworks,
      :home_assistant_connection_validator_module,
      __MODULE__.Validator
    )

    Application.put_env(:hueworks, :home_assistant_test_exchange, {:ok, oauth_credentials()})

    Application.put_env(
      :hueworks,
      :home_assistant_test_validation,
      {:ok, %{name: "Beach House", entity_count: 42}}
    )

    on_exit(fn ->
      restore_env(:home_assistant_authorization_module, previous_authorization)
      restore_env(:home_assistant_connection_validator_module, previous_validator)
      restore_env(:home_assistant_test_exchange, previous_exchange)
      restore_env(:home_assistant_test_validation, previous_validation)
      restore_env(:home_assistant_authorization_state_ttl_seconds, previous_ttl)
    end)

    :ok
  end

  test "browser authorization creates a validated OAuth bridge and continues to inventory", %{
    conn: conn
  } do
    {conn, state, authorization_url} = begin_authorization(conn)

    assert authorization_url =~ "http://ha.local:8123/auth/authorize?"
    assert URI.decode_query(URI.parse(authorization_url).query)["state"] == state

    conn = callback(conn, state, "accepted-code")
    bridge = Repo.one!(Bridge)

    assert redirected_to(conn) == "/setup?refresh_ha_inventory=#{bridge.id}"
    assert bridge.name == "Beach House"
    assert bridge.host == "ha.local:8123"
    assert bridge.external_id == "stable-ha-id"
    assert bridge.import_complete == false

    credentials = Bridge.credentials_struct(bridge)
    assert credentials.auth_type == "oauth"
    assert credentials.access_token == "browser-access"
    assert credentials.refresh_token == "browser-refresh"
    assert credentials.auth_status == "ready"
    assert is_nil(credentials.token)
  end

  test "authorization state is single use and a replay cannot create another bridge", %{
    conn: conn
  } do
    {conn, state, _authorization_url} = begin_authorization(conn)
    conn = callback(conn, state, "accepted-code")

    assert Repo.aggregate(Bridge, :count) == 1

    replayed = callback(conn, state, "accepted-code")

    assert redirected_to(replayed) == "/config/bridges/new?type=ha"
    assert Repo.aggregate(Bridge, :count) == 1
  end

  test "denied, expired, and failed callbacks leave no partial bridge rows", %{conn: conn} do
    {denied_conn, denied_state, _authorization_url} = begin_authorization(conn)

    denied_conn =
      denied_conn
      |> recycle()
      |> get(
        "#{@callback_path}?#{URI.encode_query(%{"state" => denied_state, "error" => "access_denied"})}"
      )

    assert redirected_to(denied_conn) == "/config/bridges/new?type=ha"
    assert Repo.aggregate(Bridge, :count) == 0

    Application.put_env(
      :hueworks,
      :home_assistant_test_exchange,
      {:error, :authorization_failed}
    )

    {failed_conn, failed_state, _authorization_url} = begin_authorization(denied_conn)
    failed_conn = callback(failed_conn, failed_state, "rejected-code")

    assert redirected_to(failed_conn) == "/config/bridges/new?type=ha"
    assert Repo.aggregate(Bridge, :count) == 0

    Application.put_env(:hueworks, :home_assistant_authorization_state_ttl_seconds, -1)
    {expired_conn, expired_state, _authorization_url} = begin_authorization(failed_conn)
    expired_conn = callback(expired_conn, expired_state, "accepted-code")

    assert redirected_to(expired_conn) == "/config/bridges/new?type=ha"
    assert Repo.aggregate(Bridge, :count) == 0
  end

  test "validation failure and duplicate identity do not create a bridge", %{conn: conn} do
    Application.put_env(
      :hueworks,
      :home_assistant_test_validation,
      {:error, :inventory_unavailable}
    )

    {invalid_conn, invalid_state, _authorization_url} = begin_authorization(conn)
    invalid_conn = callback(invalid_conn, invalid_state, "accepted-code")

    assert redirected_to(invalid_conn) == "/config/bridges/new?type=ha"
    assert Repo.aggregate(Bridge, :count) == 0

    Application.put_env(
      :hueworks,
      :home_assistant_test_validation,
      {:ok, %{name: "Beach House", entity_count: 42}}
    )

    _existing = insert_ha_bridge!(%{external_id: "stable-ha-id", host: "other-ha.local:8123"})
    {duplicate_conn, duplicate_state, _authorization_url} = begin_authorization(invalid_conn)
    duplicate_conn = callback(duplicate_conn, duplicate_state, "accepted-code")

    assert redirected_to(duplicate_conn) == "/config/bridges/new?type=ha"
    assert Repo.aggregate(Bridge, :count) == 1
  end

  test "reauthorization replaces credentials without replacing bridge configuration", %{
    conn: conn
  } do
    bridge =
      insert_ha_bridge!(%{
        external_id: "existing-ha-id",
        host: "https://ha.example.test:8443",
        import_complete: true,
        credentials: %{"token" => "old-manual-token"}
      })

    authorize_conn =
      get(conn, "#{@authorize_path}?#{URI.encode_query(%{"bridge_id" => bridge.id})}")

    state = authorization_state(authorize_conn)
    callback_conn = callback(authorize_conn, state, "accepted-code")
    updated = Repo.get!(Bridge, bridge.id)

    assert redirected_to(callback_conn) == "/config/bridges"
    assert Repo.aggregate(Bridge, :count) == 1
    assert updated.host == bridge.host
    assert updated.external_id == bridge.external_id
    assert updated.import_complete
    assert Bridge.credentials_struct(updated).access_token == "browser-access"
    assert Bridge.credentials_struct(updated).auth_status == "ready"
  end

  defmodule Authorization do
    def authorize(host, canonical_url, state) do
      Hueworks.HomeAssistant.Authorization.authorize(host, canonical_url, state)
    end

    def exchange_code(_host, _client_id, _code) do
      Application.fetch_env!(:hueworks, :home_assistant_test_exchange)
    end
  end

  defmodule Validator do
    def validate(_host, _access_token) do
      Application.fetch_env!(:hueworks, :home_assistant_test_validation)
    end
  end

  defp begin_authorization(conn) do
    query = URI.encode_query(%{"host" => "ha.local:8123", "external_id" => "stable-ha-id"})
    conn = conn |> recycle() |> get("#{@authorize_path}?#{query}")
    url = redirected_to(conn)
    {conn, URI.decode_query(URI.parse(url).query)["state"], url}
  end

  defp authorization_state(conn) do
    conn
    |> redirected_to()
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.fetch!("state")
  end

  defp callback(conn, state, code) do
    query = URI.encode_query(%{"state" => state, "code" => code})
    conn |> recycle() |> get("#{@callback_path}?#{query}")
  end

  defp insert_ha_bridge!(attrs) do
    defaults = %{
      type: :ha,
      name: "Existing Home Assistant",
      host: "ha.local:8123",
      credentials: %{"token" => "manual-token"},
      import_complete: false
    }

    %Bridge{}
    |> Bridge.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp oauth_credentials do
    %{
      "auth_type" => "oauth",
      "access_token" => "browser-access",
      "refresh_token" => "browser-refresh",
      "expires_at" => System.system_time(:second) + 1800,
      "client_id" => "http://localhost:4002",
      "auth_status" => "ready"
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:hueworks, key)
  defp restore_env(key, value), do: Application.put_env(:hueworks, key, value)
end
