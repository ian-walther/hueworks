defmodule Hueworks.ApiTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Api
  alias Hueworks.Control.{DesiredState, State, TraceBuffer}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, PresenceInput, Room, Scene}

  setup do
    TraceBuffer.clear()
    :ok
  end

  test "returns concise room, light, and group projections without persisted secrets" do
    fixture = fixture()

    _ = State.put(:light, fixture.lamp.id, %{power: :on, brightness: 65, kelvin: 2700})
    _ = State.put(:light, fixture.accent.id, %{power: :off, brightness: 1})
    _ = DesiredState.put(:light, fixture.lamp.id, %{power: :on, brightness: 70, kelvin: 2700})

    assert {:ok, room} = Api.room(fixture.room.id)
    assert room.kind == "room"
    assert room.id == fixture.room.id
    assert room.active_scene.id == fixture.scene.id
    assert room.active_scene.power_overrides == %{}
    assert [%{id: presence_id, occupied: true}] = room.presence_inputs
    assert presence_id == fixture.presence_input.id

    assert Enum.map(room.lights, & &1.id) == [
             fixture.linked_lamp.id,
             fixture.accent.id,
             fixture.lamp.id
           ]

    assert [%{id: group_id}] = room.groups
    assert group_id == fixture.group.id

    assert {:ok, lamp} = Api.light(fixture.lamp.id)
    assert lamp.kind == "light"
    assert lamp.name == "Office Lamp"
    assert lamp.physical_state == %{"power" => "on", "brightness" => 65, "kelvin" => 2700}
    assert lamp.desired_state == %{"power" => "on", "brightness" => 70, "kelvin" => 2700}
    assert lamp.desired_revision == 1
    assert %{"min" => 2000, "max" => 6500} = lamp.capabilities.kelvin_range
    assert lamp.exports == %{"home_assistant" => "none", "homekit" => "none"}
    assert [%{id: linked_id, kind: "light"}] = lamp.canonical_dependents
    assert linked_id == fixture.linked_lamp.id
    assert [%{id: containing_group_id, kind: "group"}] = lamp.groups
    assert containing_group_id == fixture.group.id
    refute Map.has_key?(lamp, :metadata)
    refute inspect(lamp) =~ "bridge-api-key"

    assert {:ok, group} = Api.group(fixture.group.id)
    assert group.kind == "group"
    assert group.member_light_ids == [fixture.lamp.id, fixture.accent.id]
    assert group.member_power_summary == "mixed"
    assert group.bridge_reported_state == nil
    assert group.physical_state == nil
    assert Enum.map(group.member_lights, & &1.id) == [fixture.accent.id, fixture.lamp.id]
    refute Map.has_key?(group, :metadata)
  end

  test "keeps unavailable physical state distinct from desired state and supports debug projections" do
    fixture = fixture()
    _ = DesiredState.put(:light, fixture.lamp.id, %{power: :on})

    TraceBuffer.record(
      %{trace_id: "api-debug-1", source: "api.light_control", room_id: fixture.room.id},
      :planned,
      %{type: :light, id: fixture.lamp.id, desired: %{power: :on}, planner_ms: 4}
    )

    assert {:ok, lamp} = Api.light(fixture.lamp.id)
    assert lamp.physical_state == nil
    assert lamp.physical_observed_at == nil
    assert lamp.desired_state == %{"power" => "on"}
    assert %DateTime{} = DesiredState.updated_at(:light, fixture.lamp.id)

    assert {:ok, debug} = Api.debug_light(fixture.lamp.id)
    assert debug.kind == "light"
    assert [trace] = debug.diagnostics.recent_traces
    assert trace.trace_id == "api-debug-1"
    assert trace.recorded_at =~ "T"
    assert trace.desired == %{"power" => "on"}

    assert %{events: [filtered]} = Api.traces(entity_kind: :light, entity_id: fixture.lamp.id)
    assert filtered.trace_id == "api-debug-1"
  end

  test "returns explicit not-found errors and concise status counts" do
    fixture = fixture()

    assert {:error, :not_found} = Api.light(-1)
    assert {:error, :not_found} = Api.group(-1)
    assert {:error, :not_found} = Api.room(-1)

    status = Api.status()
    assert status.api_version == "v1"
    assert status.counts.rooms == 1
    assert status.counts.lights == 3
    assert status.counts.groups == 1
    assert status.runtime.control_state_ready
    assert status.runtime.desired_state_ready
    assert status.runtime.trace_buffer_ready
    assert status.server_time =~ "T"
    assert fixture.bridge.id > 0
  end

  test "returns a concise room index with counts instead of repeating room topology" do
    fixture = fixture()

    assert [room] = Api.rooms()
    assert room.id == fixture.room.id
    assert room.active_scene.id == fixture.scene.id
    assert room.entity_counts == %{lights: 3, groups: 1, scenes: 1, presence_inputs: 1}
    refute Map.has_key?(room, :lights)
    refute Map.has_key?(room, :groups)
  end

  defp fixture do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        name: "Hue",
        type: :hue,
        host: "api-fixture-hue",
        credentials: %{api_key: "bridge-api-key"}
      })

    lamp =
      Repo.insert!(%Light{
        name: "Office Lamp",
        display_name: "Office Lamp",
        source: :hue,
        source_id: "office-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        metadata: %{"secret" => "must-not-leak"}
      })

    accent =
      Repo.insert!(%Light{
        name: "Office Accent",
        display_name: "Office Accent",
        source: :hue,
        source_id: "office-accent",
        bridge_id: bridge.id,
        room_id: room.id
      })

    linked_lamp =
      Repo.insert!(%Light{
        name: "Linked Office Lamp",
        display_name: "Linked Office Lamp",
        source: :ha,
        source_id: "linked-office-lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        canonical_light_id: lamp.id
      })

    group =
      Repo.insert!(%Group{
        name: "Office Lights",
        display_name: "Office Lights",
        source: :hue,
        source_id: "office-lights",
        bridge_id: bridge.id,
        room_id: room.id,
        metadata: %{"secret" => "must-not-leak"}
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: lamp.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: accent.id})

    scene = Repo.insert!(%Scene{name: "Focus", display_name: "Focus", room_id: room.id})
    assert {:ok, _active_scene} = ActiveScenes.set_active(scene)

    presence_input =
      Repo.insert!(%PresenceInput{room_id: room.id, name: "Desk", occupied: true})

    %{
      room: room,
      bridge: bridge,
      lamp: lamp,
      accent: accent,
      linked_lamp: linked_lamp,
      group: group,
      scene: scene,
      presence_input: presence_input
    }
  end
end
