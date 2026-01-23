defmodule Hueworks.Import.MaterializeTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Materialize
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light, Room}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "materializes rooms, lights, groups, and memberships while preserving edits" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :ha,
        name: "Home Assistant",
        host: "10.0.0.2",
        credentials: %{"token" => "token"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    existing_light =
      %Light{}
      |> Light.changeset(%{
        name: "Old Lamp",
        display_name: "Custom Lamp",
        source: :ha,
        source_id: "light.office_lamp",
        bridge_id: bridge.id,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        enabled: false
      })
      |> Repo.insert!()

    existing_group =
      %Group{}
      |> Group.changeset(%{
        name: "Old Group",
        display_name: "Custom Group",
        source: :ha,
        source_id: "light.office_group",
        bridge_id: bridge.id,
        enabled: false
      })
      |> Repo.insert!()

    normalized = load_fixture("materialize_ha.json")

    :ok = Materialize.materialize(bridge, normalized)

    room = Repo.get_by!(Room, name: "Office")

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "light.office_lamp")
    assert light.room_id == room.id
    assert light.display_name == "Custom Lamp"
    refute light.enabled
    assert light.actual_min_kelvin == 2700
    assert light.actual_max_kelvin == 6500
    assert light.reported_min_kelvin == 2000
    assert light.reported_max_kelvin == 6500

    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "light.office_group")
    assert group.room_id == room.id
    assert group.display_name == "Custom Group"
    refute group.enabled

    assert Repo.get_by(GroupLight, group_id: group.id, light_id: light.id)
    assert Repo.get_by(Light, id: existing_light.id)
    assert Repo.get_by(Group, id: existing_group.id)

    studio = Repo.get_by!(Room, name: "Studio")
    studio_group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "light.studio_group")
    assert studio_group.room_id == studio.id
  end

  test "materializes Hue metadata and bridge_host" do
    bridge =
      %Bridge{}
      |> Bridge.changeset(%{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.9",
        credentials: %{"api_key" => "key"},
        import_complete: false,
        enabled: true
      })
      |> Repo.insert!()

    normalized = load_fixture("materialize_hue.json")

    :ok = Materialize.materialize(bridge, normalized)

    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "1")
    assert light.metadata["bridge_host"] == "10.0.0.9"

    group = Repo.get_by!(Group, bridge_id: bridge.id, source_id: "2")
    assert group.metadata["bridge_host"] == "10.0.0.9"
  end

  defp load_fixture(name) do
    path = Path.join(["test", "fixtures", "normalize", name])
    path |> File.read!() |> Jason.decode!()
  end
end
