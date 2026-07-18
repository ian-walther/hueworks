defmodule Hueworks.ApiTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.ActiveScenes
  alias Hueworks.Api
  alias Hueworks.Control.{DesiredState, State, TraceBuffer}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light, PresenceInput, Area, Scene}

  setup do
    TraceBuffer.clear()
    :ok
  end

  test "returns concise area, light, and group projections without persisted secrets" do
    fixture = fixture()

    _ = State.put(:light, fixture.lamp.id, %{power: :on, brightness: 65, kelvin: 2700})
    _ = State.put(:light, fixture.accent.id, %{power: :off, brightness: 1})
    _ = DesiredState.put(:light, fixture.lamp.id, %{power: :on, brightness: 70, kelvin: 2700})

    assert {:ok, area} = Api.area(fixture.area.id)
    assert area.kind == "area"
    assert area.id == fixture.area.id
    assert area.active_scene.id == fixture.scene.id
    assert area.active_scene.power_overrides == %{}
    assert [%{id: presence_id, occupied: true}] = area.presence_inputs
    assert presence_id == fixture.presence_input.id

    assert Enum.map(area.lights, & &1.id) == [
             fixture.linked_lamp.id,
             fixture.accent.id,
             fixture.lamp.id
           ]

    assert [%{id: group_id}] = area.groups
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
      %{trace_id: "api-debug-1", source: "api.light_control", area_id: fixture.area.id},
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
    assert {:error, :not_found} = Api.area(-1)

    status = Api.status()
    assert status.api_version == "v1"
    assert status.counts.areas == 1
    assert status.counts.lights == 3
    assert status.counts.groups == 1
    assert status.runtime.control_state_ready
    assert status.runtime.desired_state_ready
    assert status.runtime.trace_buffer_ready
    assert status.server_time =~ "T"
    assert fixture.bridge.id > 0
  end

  test "returns a concise area index with counts instead of repeating area topology" do
    fixture = fixture()

    assert [area] = Api.areas()
    assert area.id == fixture.area.id
    assert area.active_scene.id == fixture.scene.id
    assert area.entity_counts == %{lights: 3, groups: 1, scenes: 1, presence_inputs: 1}
    refute Map.has_key?(area, :lights)
    refute Map.has_key?(area, :groups)
  end

  test "searches entity names with explicit match and controllability metadata" do
    fixture = fixture()

    hidden_duplicate =
      Repo.insert!(%Light{
        name: "Office Lamp",
        display_name: "Office Lamp",
        source: :ha,
        source_id: "hidden-office-lamp",
        bridge_id: fixture.bridge.id,
        canonical_light_id: fixture.lamp.id,
        enabled: false
      })

    search = Api.search_entities("  office lamp  ")

    assert search.query == "office lamp"
    assert search.exact_match_count == 2
    assert search.exact_controllable_match_count == 1

    assert [
             %{
               id: lamp_id,
               kind: "light",
               match: "exact",
               controllable: true,
               area_id: area_id,
               area_name: "Office",
               canonical_id: nil
             },
             %{
               id: duplicate_id,
               kind: "light",
               match: "exact",
               controllable: false,
               enabled: false,
               canonical_id: canonical_id,
               area_id: nil,
               area_name: nil
             },
             %{id: linked_id, kind: "light", match: "partial", controllable: false}
           ] = search.results

    assert lamp_id == fixture.lamp.id
    assert area_id == fixture.area.id
    assert duplicate_id == hidden_duplicate.id
    assert canonical_id == fixture.lamp.id
    assert linked_id == fixture.linked_lamp.id
    refute inspect(search) =~ "must-not-leak"
  end

  test "filters entity searches by kind and area while matching bridge names" do
    fixture = fixture()
    other_area = Repo.insert!(%Area{name: "Studio"})

    other_lamp =
      Repo.insert!(%Light{
        name: "Office Lamp",
        display_name: "Studio Office Lamp",
        source: :hue,
        source_id: "studio-office-lamp",
        bridge_id: fixture.bridge.id,
        area_id: other_area.id
      })

    group_search = Api.search_entities("office", kind: :group)
    assert [%{id: group_id, kind: "group", match: "prefix"}] = group_search.results
    assert group_id == fixture.group.id

    area_search = Api.search_entities("office lamp", area_id: other_area.id)
    assert area_search.exact_match_count == 1
    assert area_search.exact_controllable_match_count == 1

    assert [%{id: lamp_id, kind: "light", match: "exact", area_id: area_id}] =
             area_search.results

    assert lamp_id == other_lamp.id
    assert area_id == other_area.id
  end

  defp fixture do
    area = Repo.insert!(%Area{name: "Office"})

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
        area_id: area.id,
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
        area_id: area.id
      })

    linked_lamp =
      Repo.insert!(%Light{
        name: "Linked Office Lamp",
        display_name: "Linked Office Lamp",
        source: :ha,
        source_id: "linked-office-lamp",
        bridge_id: bridge.id,
        area_id: area.id,
        canonical_light_id: lamp.id
      })

    group =
      Repo.insert!(%Group{
        name: "Office Lights",
        display_name: "Office Lights",
        source: :hue,
        source_id: "office-lights",
        bridge_id: bridge.id,
        area_id: area.id,
        metadata: %{"secret" => "must-not-leak"}
      })

    Repo.insert!(%GroupLight{group_id: group.id, light_id: lamp.id})
    Repo.insert!(%GroupLight{group_id: group.id, light_id: accent.id})

    scene = Repo.insert!(%Scene{name: "Focus", display_name: "Focus", area_id: area.id})
    assert {:ok, _active_scene} = ActiveScenes.set_active(scene)

    presence_input =
      Repo.insert!(%PresenceInput{area_id: area.id, name: "Desk", occupied: true})

    %{
      area: area,
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
