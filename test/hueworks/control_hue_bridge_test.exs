defmodule Hueworks.Control.HueBridgeTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.HueBridge
  alias Hueworks.Repo
  alias Hueworks.Schemas.Light

  test "credentials_for resolves Hue bridge credentials through bridge_id without metadata host" do
    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.94",
        credentials: %{"api_key" => "test-api-key"}
      })

    light =
      Repo.insert!(%Light{
        name: "Hue Lamp",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        enabled: true,
        metadata: %{}
      })

    assert HueBridge.credentials_for(light) == {:ok, "192.168.1.94", "test-api-key"}
  end

  test "credentials_for ignores stale imported bridge_host metadata" do
    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.95",
        credentials: %{"api_key" => "current-api-key"}
      })

    light =
      Repo.insert!(%Light{
        name: "Hue Lamp",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        enabled: true,
        metadata: %{"bridge_host" => "192.168.1.10"}
      })

    assert HueBridge.credentials_for(light) == {:ok, "192.168.1.95", "current-api-key"}
  end
end
