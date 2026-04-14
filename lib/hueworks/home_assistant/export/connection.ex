defmodule Hueworks.HomeAssistant.Export.Connection do
  @moduledoc false

  require Logger

  def start(client_id, server_pid, config, topic_filters) when is_pid(server_pid) do
    start_opts =
      [
        client_id: client_id,
        handler: {Hueworks.HomeAssistant.Export.Handler, [server_pid, client_id, topic_filters]},
        server: {Tortoise.Transport.Tcp, host: String.to_charlist(config.host), port: config.port}
      ]
      |> maybe_put_auth(config)

    case supervisor_module().start_child(start_opts) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.warning(
          "Failed to start Home Assistant export MQTT connection: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    dynamic_supervisor_module().terminate_child(tortoise_supervisor_name(), pid)
  end

  def publish(client_id, topic, payload, opts) when is_binary(client_id) do
    publish_opts = [qos: 0, retain: Keyword.get(opts, :retain, false)]

    case tortoise_module().publish(client_id, topic, payload, publish_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish Home Assistant export MQTT payload: #{inspect(reason)}")
        :ok
    end
  end

  def alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  def alive?(_pid), do: false

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
    case Application.get_env(:hueworks, :ha_export_tortoise_module) do
      nil -> Tortoise
      module -> module
    end
  end

  defp supervisor_module do
    case Application.get_env(:hueworks, :ha_export_tortoise_supervisor_module) do
      nil -> Tortoise.Supervisor
      module -> module
    end
  end

  defp dynamic_supervisor_module do
    case Application.get_env(:hueworks, :ha_export_dynamic_supervisor_module) do
      nil -> DynamicSupervisor
      module -> module
    end
  end

  defp tortoise_supervisor_name do
    case Application.get_env(:hueworks, :ha_export_tortoise_supervisor_name) do
      nil -> Tortoise.Supervisor
      name -> name
    end
  end
end
