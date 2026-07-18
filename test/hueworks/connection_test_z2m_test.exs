defmodule Hueworks.ConnectionTest.Z2MTest do
  use ExUnit.Case, async: false

  alias Hueworks.ConnectionTest.Z2M

  defmodule SnapshotSuccess do
    def fetch(config) do
      send(self(), {:snapshot_config, config})

      {:ok,
       %{
         bridge_info: %{"version" => "2.1.0"},
         devices: [%{"friendly_name" => "Lamp"}],
         groups: [%{"friendly_name" => "Room"}]
       }}
    end
  end

  defmodule SnapshotFailure do
    def fetch(_config),
      do: {:error, "timed out waiting for MQTT snapshot topics: custom/bridge/groups"}
  end

  setup do
    original = Application.get_env(:hueworks, :z2m_snapshot_module)

    on_exit(fn ->
      if original do
        Application.put_env(:hueworks, :z2m_snapshot_module, original)
      else
        Application.delete_env(:hueworks, :z2m_snapshot_module)
      end
    end)

    :ok
  end

  test "returns validation error when host is missing" do
    assert {:error, "Z2M test failed: host is required."} == Z2M.test("", %{})
  end

  test "validates the retained Zigbee2MQTT snapshot with the pending connection details" do
    Application.put_env(:hueworks, :z2m_snapshot_module, SnapshotSuccess)

    assert {:ok, "Zigbee2MQTT (1 device, 1 group)"} ==
             Z2M.test("mqtt.local", %{
               "broker_port" => "1884",
               "username" => "hueworks",
               "password" => "secret",
               "base_topic" => "custom"
             })

    assert_received {:snapshot_config,
                     %{
                       host: "mqtt.local",
                       port: 1884,
                       username: "hueworks",
                       password: "secret",
                       base_topic: "custom"
                     }}
  end

  test "reports retained snapshot failures without exposing credentials" do
    Application.put_env(:hueworks, :z2m_snapshot_module, SnapshotFailure)

    assert {:error, message} =
             Z2M.test("mqtt.local", %{
               "username" => "hueworks",
               "password" => "do-not-leak",
               "base_topic" => "custom"
             })

    assert message =~ "Z2M test failed"
    assert message =~ "custom/bridge/groups"
    refute message =~ "do-not-leak"
  end
end
