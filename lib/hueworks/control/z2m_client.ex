defmodule Hueworks.Control.Z2MClient do
  @moduledoc false

  @connection_timeout 5_000

  def request(config, entity, payload) when is_map(config) and is_map(payload) do
    topic = "#{config.base_topic}/#{entity.source_id}/set"
    encoded = Jason.encode!(payload)
    client_id = control_client_id(config.bridge_id)

    with :ok <- ensure_connection(client_id, config),
         :ok <- publish(client_id, topic, encoded) do
      :ok
    end
  end

  def control_client_id(bridge_id), do: "hwz2mc#{bridge_id}"

  defp ensure_connection(client_id, config) do
    connection_mod = connection_module()

    case connection_mod.connection(client_id, timeout: 50) do
      {:ok, _socket} ->
        :ok

      {:error, :unknown_connection} ->
        start_connection(client_id, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_connection(client_id, config) do
    start_opts =
      [
        client_id: client_id,
        handler: {Tortoise.Handler.Default, []},
        server: {Tortoise.Transport.Tcp, host: String.to_charlist(config.host), port: config.port}
      ]
      |> maybe_put_auth(config)

    case supervisor_module().start_child(start_opts) do
      {:ok, _pid} ->
        await_connection(client_id)

      {:error, {:already_started, _pid}} ->
        await_connection(client_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_connection(client_id) do
    case connection_module().connection(client_id, timeout: @connection_timeout) do
      {:ok, _socket} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish(client_id, topic, payload) do
    case tortoise_module().publish(client_id, topic, payload, qos: 0) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_auth(opts, %{username: username, password: password}) when is_binary(username) do
    opts
    |> Keyword.put(:user_name, username)
    |> maybe_put_password(password)
  end

  defp maybe_put_auth(opts, _config), do: opts

  defp maybe_put_password(opts, password) when is_binary(password),
    do: Keyword.put(opts, :password, password)

  defp maybe_put_password(opts, _password), do: opts

  defp tortoise_module do
    Application.get_env(:hueworks, :z2m_tortoise_module, Tortoise)
  end

  defp supervisor_module do
    Application.get_env(:hueworks, :z2m_tortoise_supervisor_module, Tortoise.Supervisor)
  end

  defp connection_module do
    Application.get_env(:hueworks, :z2m_tortoise_connection_module, Tortoise.Connection)
  end
end
