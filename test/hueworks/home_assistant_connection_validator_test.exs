defmodule Hueworks.HomeAssistant.ConnectionValidatorTest do
  use ExUnit.Case, async: false

  alias Hueworks.HomeAssistant.ConnectionValidator

  setup do
    previous_connection_test =
      Application.get_env(:hueworks, :home_assistant_connection_test_module)

    previous_client = Application.get_env(:hueworks, :home_assistant_validation_client)
    previous_responses = Application.get_env(:hueworks, :home_assistant_validation_responses)
    previous_listener = Application.get_env(:hueworks, :home_assistant_validation_listener)

    Application.put_env(
      :hueworks,
      :home_assistant_connection_test_module,
      __MODULE__.ConnectionTest
    )

    Application.put_env(:hueworks, :home_assistant_validation_client, __MODULE__.Client)
    Application.put_env(:hueworks, :home_assistant_validation_listener, self())

    on_exit(fn ->
      restore_env(:home_assistant_connection_test_module, previous_connection_test)
      restore_env(:home_assistant_validation_client, previous_client)
      restore_env(:home_assistant_validation_responses, previous_responses)
      restore_env(:home_assistant_validation_listener, previous_listener)
    end)

    :ok
  end

  test "validates REST identity and the import websocket capabilities" do
    Application.put_env(:hueworks, :home_assistant_validation_responses, %{
      "config/entity_registry/list" => {:ok, [%{"entity_id" => "light.office"}]},
      "get_states" => {:ok, [%{"entity_id" => "light.office", "state" => "on"}]}
    })

    assert {:ok, %{name: "Test Home", entity_count: 1}} =
             ConnectionValidator.validate("ha.local:8123", "browser-token")

    assert_receive {:validation_connection, connection}
    refute Process.alive?(connection)
  end

  test "rejects a token that cannot read the inventory needed by import" do
    Application.put_env(:hueworks, :home_assistant_validation_responses, %{
      "config/entity_registry/list" => {:error, %{"code" => "unauthorized"}},
      "get_states" => {:ok, []}
    })

    assert {:error, :inventory_unavailable} =
             ConnectionValidator.validate("ha.local:8123", "browser-token")
  end

  defmodule ConnectionTest do
    def test(_host, "browser-token"), do: {:ok, "Test Home"}
    def test(_host, _token), do: {:error, "rejected"}
  end

  defmodule Client do
    def connect(_host, _token) do
      {:ok, connection} = Agent.start_link(fn -> :connected end)
      listener = Application.fetch_env!(:hueworks, :home_assistant_validation_listener)
      send(listener, {:validation_connection, connection})
      {:ok, connection}
    end

    def request(connection, type, %{}) when is_pid(connection) do
      :hueworks
      |> Application.fetch_env!(:home_assistant_validation_responses)
      |> Map.fetch!(type)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:hueworks, key)
  defp restore_env(key, value), do: Application.put_env(:hueworks, key, value)
end
