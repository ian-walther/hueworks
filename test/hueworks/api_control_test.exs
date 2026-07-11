defmodule Hueworks.ApiControlTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Api
  alias Hueworks.Control.{DesiredState, State, TraceBuffer}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, Room, Scene}

  setup do
    TraceBuffer.clear()
    :ok
  end

  test "controls enabled lights through the normal desired-state planner with a traceable API operation" do
    fixture = fixture()
    _ = State.put(:light, fixture.light.id, %{power: :off})

    assert {:ok, result} = Api.control_entity(:light, fixture.light.id, %{"power" => "on"})
    assert result.operation == "light_control"
    assert result.target == %{kind: "light", id: fixture.light.id}
    assert result.accepted_intent == %{"power" => "on"}
    assert result.plan.action_count == 1
    assert result.plan.bridge_count == 1
    assert is_binary(result.trace_id)
    assert DesiredState.get(:light, fixture.light.id).power == :on

    assert %{events: events} = TraceBuffer.recent(trace_id: result.trace_id)
    assert Enum.any?(events, &(&1.stage == :planned and &1.source == "api.light_control"))
  end

  test "expands a group through the existing group membership path" do
    fixture = fixture()

    assert {:ok, result} =
             Api.control_entity(:group, fixture.group.id, %{"power" => "off"})

    assert result.target == %{kind: "group", id: fixture.group.id}
    assert result.accepted_intent == %{"power" => "off"}
    assert DesiredState.get(:light, fixture.light.id).power == :off
    assert DesiredState.get(:light, fixture.other_light.id).power == :off
  end

  test "preserves normal manual-control restrictions and rejects hidden targets" do
    fixture = fixture()
    assert {:ok, _active_scene} = ActiveScenes.set_active(fixture.scene)

    assert {:error, :scene_active_manual_adjustment_not_allowed} =
             Api.control_entity(:light, fixture.light.id, %{"brightness" => 55})

    assert {:error, :not_found} =
             Api.control_entity(:light, fixture.disabled_light.id, %{"power" => "on"})

    assert {:error, :not_found} =
             Api.control_entity(:light, fixture.linked_light.id, %{"power" => "on"})
  end

  test "validates explicit controls and capabilities before changing desired state" do
    fixture = fixture()

    assert {:error, :invalid_control} =
             Api.control_entity(:light, fixture.light.id, %{"power" => "on", "brightness" => 50})

    assert {:error, :invalid_control} =
             Api.control_entity(:light, fixture.light.id, %{"brightness" => 101})

    assert {:error, :unsupported_capability} =
             Api.control_entity(:light, fixture.other_light.id, %{"kelvin" => 3000})

    assert {:error, :unsupported_capability} =
             Api.control_entity(:light, fixture.other_light.id, %{
               "color" => %{"hue" => 100, "saturation" => 50}
             })

    assert DesiredState.get(:light, fixture.light.id) == nil
  end

  test "activates and explicitly deactivates room scenes with API trace identifiers" do
    fixture = fixture()

    assert {:ok, activation} = Api.activate_scene(fixture.scene.id)
    assert activation.operation == "scene_activate"
    assert activation.target == %{kind: "scene", id: fixture.scene.id}
    assert ActiveScenes.get_for_room(fixture.room.id).scene_id == fixture.scene.id

    assert {:ok, deactivation} = Api.deactivate_room_scene(fixture.room.id)
    assert deactivation.operation == "room_scene_deactivate"
    assert deactivation.target == %{kind: "room", id: fixture.room.id}
    assert ActiveScenes.get_for_room(fixture.room.id) == nil
    assert %{events: [_ | _]} = TraceBuffer.recent(trace_id: deactivation.trace_id)
  end

  defp fixture do
    room = Repo.insert!(%Room{name: "API Control"})

    bridge =
      insert_bridge!(%{
        name: "API Control Hue",
        type: :hue,
        host: "api-control-hue",
        credentials: %{}
      })

    light =
      Repo.insert!(%Light{
        name: "API Lamp",
        display_name: "API Lamp",
        source: :hue,
        source_id: "api-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        supports_color: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    other_light =
      Repo.insert!(%Light{
        name: "API Other Lamp",
        display_name: "API Other Lamp",
        source: :hue,
        source_id: "api-other-lamp",
        bridge_id: bridge.id,
        room_id: room.id
      })

    disabled_light =
      Repo.insert!(%Light{
        name: "Disabled API Lamp",
        display_name: "Disabled API Lamp",
        source: :hue,
        source_id: "disabled-api-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        enabled: false
      })

    linked_light =
      Repo.insert!(%Light{
        name: "Linked API Lamp",
        display_name: "Linked API Lamp",
        source: :ha,
        source_id: "linked-api-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        canonical_light_id: light.id
      })

    group =
      Repo.insert!(%Group{
        name: "API Group",
        display_name: "API Group",
        source: :hue,
        source_id: "api-group",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        supports_color: true
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: light.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: other_light.id})

    scene = Repo.insert!(%Scene{name: "API Scene", room_id: room.id})

    %{
      room: room,
      bridge: bridge,
      light: light,
      other_light: other_light,
      disabled_light: disabled_light,
      linked_light: linked_light,
      group: group,
      scene: scene
    }
  end
end
