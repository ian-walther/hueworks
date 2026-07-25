defmodule Hueworks.HomeAssistant.TokenProvider do
  @moduledoc false

  use GenServer

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Bridge.Credentials

  @refresh_leeway_seconds 60

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def token_for(bridge_or_id, server \\ __MODULE__) do
    GenServer.call(server, {:token_for, bridge_or_id, false}, 15_000)
  end

  def refresh(bridge_or_id, server \\ __MODULE__) do
    GenServer.call(server, {:token_for, bridge_or_id, true}, 15_000)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:token_for, bridge_or_id, force_refresh?}, _from, state) do
    result =
      with {:ok, bridge} <- load_bridge(bridge_or_id) do
        resolve_token(bridge, force_refresh?)
      end

    {:reply, result, state}
  rescue
    _error -> {:reply, {:error, :temporarily_unavailable}, state}
  end

  defp load_bridge(%Bridge{id: id, __meta__: %{state: :loaded}}) when is_integer(id) do
    load_bridge(id)
  end

  defp load_bridge(%Bridge{} = bridge), do: {:ok, bridge}

  defp load_bridge(id) when is_integer(id) do
    case Repo.get(Bridge, id) do
      nil -> {:error, :bridge_not_found}
      bridge -> {:ok, bridge}
    end
  end

  defp load_bridge(_bridge_or_id), do: {:error, :bridge_not_found}

  defp resolve_token(bridge, force_refresh?) do
    credentials = Bridge.credentials_struct(bridge)

    cond do
      oauth_credentials?(credentials) ->
        resolve_oauth_token(bridge, credentials, force_refresh?)

      force_refresh? ->
        _ = mark_reauthorization_required(bridge, credentials)
        {:error, :reauthorization_required}

      valid_token?(credentials.token) ->
        {:ok, credentials.token}

      true ->
        {:error, :missing_token}
    end
  end

  defp resolve_oauth_token(bridge, credentials, force_refresh?) do
    cond do
      credentials.auth_status == "reauthorization_required" and not force_refresh? ->
        {:error, :reauthorization_required}

      not force_refresh? and current_access_token?(credentials) ->
        {:ok, credentials.access_token}

      true ->
        refresh_oauth_token(bridge, credentials)
    end
  end

  defp refresh_oauth_token(bridge, credentials) do
    case authorization_module().refresh(bridge.host, credentials) do
      {:ok, refreshed_attrs} ->
        with {:ok, _bridge} <- persist_credentials(bridge, refreshed_attrs) do
          {:ok, refreshed_attrs["access_token"]}
        end

      {:error, :reauthorization_required} = error ->
        _ = mark_reauthorization_required(bridge, credentials)
        error

      {:error, _reason} = error ->
        error
    end
  end

  defp persist_credentials(%Bridge{id: nil}, _attrs), do: {:ok, :transient}

  defp persist_credentials(bridge, attrs) do
    bridge
    |> Bridge.changeset(%{credentials: attrs})
    |> Repo.update()
  end

  defp mark_reauthorization_required(%Bridge{id: nil}, _credentials), do: :ok

  defp mark_reauthorization_required(bridge, credentials) do
    credentials
    |> Credentials.dump()
    |> Map.put("auth_status", "reauthorization_required")
    |> then(&persist_credentials(bridge, &1))

    :ok
  end

  defp oauth_credentials?(%Credentials{auth_type: "oauth"}), do: true
  defp oauth_credentials?(%Credentials{refresh_token: token}), do: valid_token?(token)

  defp current_access_token?(credentials) do
    valid_token?(credentials.access_token) and is_integer(credentials.expires_at) and
      credentials.expires_at > System.system_time(:second) + refresh_leeway_seconds()
  end

  defp valid_token?(token), do: is_binary(token) and token not in ["", "CHANGE_ME"]

  defp refresh_leeway_seconds do
    Application.get_env(
      :hueworks,
      :home_assistant_token_refresh_leeway_seconds,
      @refresh_leeway_seconds
    )
  end

  defp authorization_module do
    Application.get_env(
      :hueworks,
      :home_assistant_authorization_module,
      Hueworks.HomeAssistant.Authorization
    )
  end
end
