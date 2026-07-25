defmodule Hueworks.HomeAssistant.ConnectionValidator do
  @moduledoc false

  def validate(host, access_token) do
    with {:ok, name} <- validate_identity(host, access_token),
         {:ok, connection} <- connect(host, access_token) do
      validate_inventory(connection, name)
    end
  end

  defp validate_identity(host, access_token) do
    case connection_test_module().test(host, access_token) do
      {:ok, name} when is_binary(name) and name != "" -> {:ok, name}
      :ok -> {:ok, "Home Assistant"}
      _ -> {:error, :connection_rejected}
    end
  rescue
    _error -> {:error, :connection_unavailable}
  end

  defp connect(host, access_token) do
    case client_module().connect(host, access_token) do
      {:ok, connection} -> {:ok, connection}
      {:error, :unauthorized} -> {:error, :connection_rejected}
      _ -> {:error, :connection_unavailable}
    end
  rescue
    _error -> {:error, :connection_unavailable}
  end

  defp validate_inventory(connection, name) do
    result =
      with {:ok, entities} when is_list(entities) <-
             client_module().request(connection, "config/entity_registry/list", %{}),
           {:ok, states} when is_list(states) <-
             client_module().request(connection, "get_states", %{}) do
        {:ok, %{name: name, entity_count: length(entities)}}
      else
        _ -> {:error, :inventory_unavailable}
      end

    close_connection(connection)
    result
  rescue
    _error ->
      close_connection(connection)
      {:error, :inventory_unavailable}
  end

  defp close_connection(connection) when is_pid(connection) and connection != self() do
    GenServer.stop(connection, :normal, 1_000)
  catch
    :exit, _reason -> :ok
  end

  defp close_connection(_connection), do: :ok

  defp connection_test_module do
    Application.get_env(
      :hueworks,
      :home_assistant_connection_test_module,
      Hueworks.ConnectionTest.HomeAssistant
    )
  end

  defp client_module do
    Application.get_env(
      :hueworks,
      :home_assistant_validation_client,
      Hueworks.Import.Fetch.HomeAssistant.Client
    )
  end
end
