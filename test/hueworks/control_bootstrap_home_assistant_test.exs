defmodule Hueworks.Control.Bootstrap.HomeAssistantTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Bootstrap.HomeAssistant

  test "bootstrap does not crash when multiple enabled Home Assistant bridges exist" do
    insert_bridge!(%{
      type: :ha,
      name: "HA One",
      host: "ha-one.local",
      credentials: %{},
      enabled: true
    })

    insert_bridge!(%{
      type: :ha,
      name: "HA Two",
      host: "ha-two.local",
      credentials: %{},
      enabled: true
    })

    assert :ok == HomeAssistant.run()
  end
end
