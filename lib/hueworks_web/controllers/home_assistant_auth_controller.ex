defmodule HueworksWeb.HomeAssistantAuthController do
  use Phoenix.Controller

  import Plug.Conn, only: [get_session: 2, put_session: 3]

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Util
  alias HueworksApp.Cache

  @pending_session_key "home_assistant_authorizations"
  @default_state_ttl_seconds 600
  @max_pending_states 5

  def authorize(conn, %{"bridge_id" => bridge_id}) do
    case load_home_assistant_bridge(bridge_id) do
      %Bridge{} = bridge -> begin_authorization(conn, bridge.host, bridge.external_id, bridge.id)
      nil -> authorization_error(conn, "That Home Assistant connection no longer exists.")
    end
  end

  def authorize(conn, %{"host" => host} = params) do
    begin_authorization(conn, host, Util.blank_to_nil(params["external_id"]), nil)
  end

  def authorize(conn, _params) do
    authorization_error(conn, "Choose a Home Assistant instance before authorizing it.")
  end

  def callback(conn, params) do
    {conn, pending} = pop_pending_authorization(conn, params["state"])

    cond do
      not valid_pending?(pending) ->
        authorization_error(conn, "Home Assistant authorization expired or was already used.")

      is_binary(params["error"]) ->
        authorization_error(conn, "Home Assistant authorization was cancelled.", pending)

      not valid_code?(params["code"]) ->
        authorization_error(conn, "Home Assistant did not return an authorization code.", pending)

      true ->
        complete_authorization(conn, pending, params["code"])
    end
  end

  defp begin_authorization(conn, host, external_id, bridge_id) do
    state = random_state()

    case authorization_module().authorize(host, HueworksWeb.Endpoint.url(), state) do
      {:ok, authorization} ->
        pending = %{
          "host" => host,
          "external_id" => external_id,
          "bridge_id" => bridge_id,
          "client_id" => authorization.client_id,
          "inserted_at" => System.system_time(:second)
        }

        conn
        |> put_pending_authorization(state, pending)
        |> redirect(external: authorization.url)

      {:error, :invalid_callback_url} ->
        authorization_error(
          conn,
          "HueWorks needs a usable browser URL before Home Assistant authorization can begin."
        )

      {:error, _reason} ->
        authorization_error(conn, "That Home Assistant address cannot be authorized.")
    end
  end

  defp complete_authorization(conn, pending, code) do
    with {:ok, credentials} <-
           authorization_module().exchange_code(pending["host"], pending["client_id"], code),
         access_token when is_binary(access_token) and access_token != "" <-
           credentials["access_token"],
         {:ok, validation} <- validator_module().validate(pending["host"], access_token),
         {:ok, bridge, operation} <- save_bridge(pending, validation, credentials) do
      Cache.delete(:bridge_credentials, {:ha, bridge.id})

      case operation do
        :created ->
          conn
          |> put_flash(:info, "Home Assistant authorized. Reading inventory before Area design.")
          |> redirect(to: "/setup?refresh_ha_inventory=#{bridge.id}")

        :reauthorized ->
          conn
          |> put_flash(:info, "Home Assistant authorization refreshed.")
          |> redirect(to: "/config/bridges")
      end
    else
      {:error, %Ecto.Changeset{}} ->
        authorization_error(
          conn,
          "That Home Assistant instance is already configured.",
          pending
        )

      {:error, :bridge_not_found} ->
        authorization_error(conn, "That Home Assistant connection no longer exists.", pending)

      {:error, :connection_rejected} ->
        authorization_error(conn, "Home Assistant rejected the new authorization.", pending)

      {:error, :inventory_unavailable} ->
        authorization_error(
          conn,
          "Authorization succeeded, but HueWorks could not read Home Assistant inventory.",
          pending
        )

      {:error, _reason} ->
        authorization_error(conn, "Home Assistant authorization could not be completed.", pending)

      _ ->
        authorization_error(conn, "Home Assistant returned incomplete credentials.", pending)
    end
  end

  defp save_bridge(%{"bridge_id" => bridge_id}, _validation, credentials)
       when is_integer(bridge_id) do
    case load_home_assistant_bridge(bridge_id) do
      nil ->
        {:error, :bridge_not_found}

      bridge ->
        bridge
        |> Bridge.changeset(%{credentials: oauth_credentials(credentials)})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated, :reauthorized}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp save_bridge(pending, validation, credentials) do
    %Bridge{}
    |> Bridge.changeset(%{
      type: :ha,
      name: validation.name,
      host: pending["host"],
      external_id: pending["external_id"],
      credentials: oauth_credentials(credentials),
      enabled: true,
      import_complete: false
    })
    |> Repo.insert()
    |> case do
      {:ok, bridge} -> {:ok, bridge, :created}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp oauth_credentials(credentials), do: Map.put(credentials, "token", nil)

  defp put_pending_authorization(conn, state, pending) do
    pending_states =
      conn
      |> get_session(@pending_session_key)
      |> normalize_pending_states()
      |> prune_pending_states()
      |> Map.put(state, pending)
      |> bound_pending_states()

    put_session(conn, @pending_session_key, pending_states)
  end

  defp pop_pending_authorization(conn, state) when is_binary(state) and state != "" do
    pending_states = conn |> get_session(@pending_session_key) |> normalize_pending_states()
    {pending, remaining} = Map.pop(pending_states, state)
    {put_session(conn, @pending_session_key, remaining), pending}
  end

  defp pop_pending_authorization(conn, _state) do
    {conn, nil}
  end

  defp normalize_pending_states(states) when is_map(states), do: states
  defp normalize_pending_states(_states), do: %{}

  defp prune_pending_states(states) do
    Map.filter(states, fn {_state, pending} -> valid_pending?(pending) end)
  end

  defp bound_pending_states(states) do
    states
    |> Enum.sort_by(fn {_state, pending} -> pending["inserted_at"] || 0 end, :desc)
    |> Enum.take(@max_pending_states)
    |> Map.new()
  end

  defp valid_pending?(%{"host" => host, "client_id" => client_id, "inserted_at" => inserted_at}) do
    is_binary(host) and host != "" and is_binary(client_id) and client_id != "" and
      is_integer(inserted_at) and
      inserted_at >= System.system_time(:second) - state_ttl_seconds()
  end

  defp valid_pending?(_pending), do: false

  defp valid_code?(code), do: is_binary(code) and code != ""

  defp load_home_assistant_bridge(id) when is_integer(id) do
    case Repo.get(Bridge, id) do
      %Bridge{type: :ha} = bridge -> bridge
      _ -> nil
    end
  end

  defp load_home_assistant_bridge(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> load_home_assistant_bridge(parsed)
      _ -> nil
    end
  end

  defp load_home_assistant_bridge(_id), do: nil

  defp authorization_error(conn, message, pending \\ nil) do
    destination =
      if is_integer(pending && pending["bridge_id"]),
        do: "/config/bridges",
        else: "/config/bridges/new?type=ha"

    conn
    |> put_flash(:error, message)
    |> redirect(to: destination)
  end

  defp random_state do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp state_ttl_seconds do
    Application.get_env(
      :hueworks,
      :home_assistant_authorization_state_ttl_seconds,
      @default_state_ttl_seconds
    )
  end

  defp authorization_module do
    Application.get_env(
      :hueworks,
      :home_assistant_authorization_module,
      Hueworks.HomeAssistant.Authorization
    )
  end

  defp validator_module do
    Application.get_env(
      :hueworks,
      :home_assistant_connection_validator_module,
      Hueworks.HomeAssistant.ConnectionValidator
    )
  end
end
