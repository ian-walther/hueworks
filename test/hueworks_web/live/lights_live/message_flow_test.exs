defmodule HueworksWeb.LightsLive.MessageFlowTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light, Room}
  alias HueworksWeb.LightsLive.Loader
  alias HueworksWeb.LightsLive.MessageFlow

  test "refresh reloads assigns and sets status" do
    room = Repo.insert!(%Room{name: "Refresh Room"})

    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.210",
        credentials: %{"api_key" => "test"}
      })

    _light =
      Repo.insert!(%Light{
        name: "Refresh Lamp",
        source: :hue,
        source_id: "refresh-lamp",
        bridge_id: bridge.id,
        room_id: room.id
      })

    assigns = Loader.mount_assigns(%{}, nil)
    updated = MessageFlow.refresh(assigns)

    assert updated.status == "Reloaded database snapshot"
    assert Enum.any?(updated.lights, &(&1.name == "Refresh Lamp"))
  end

  test "info_updates routes live control-state messages into assign updates" do
    room = Repo.insert!(%Room{name: "Info Room"})

    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.211",
        credentials: %{"api_key" => "test"}
      })

    light =
      Repo.insert!(%Light{
        name: "Info Lamp",
        source: :hue,
        source_id: "info-lamp",
        bridge_id: bridge.id,
        room_id: room.id
      })

    group =
      Repo.insert!(%Group{
        name: "Info Group",
        source: :hue,
        source_id: "info-group",
        bridge_id: bridge.id,
        room_id: room.id
      })

    assigns = Loader.mount_assigns(%{}, nil)

    assert {:ok, %{light_state: light_state}} =
             MessageFlow.info_updates({:control_state, :light, light.id, %{power: :on}}, assigns)

    assert light_state[light.id][:power] == :on

    assert {:ok, %{group_state: group_state}} =
             MessageFlow.info_updates({:control_state, :group, group.id, %{power: :off}}, assigns)

    assert group_state[group.id][:power] == :off

    assert :ignore = MessageFlow.info_updates(:unexpected, assigns)
  end
end
