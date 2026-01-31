defmodule Hueworks.Import.NormalizeFromDbTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Import.NormalizeFromDb
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light}

  test "builds normalized map from stored normalized_json" do
    bridge =
      Repo.insert!(%Bridge{
        type: :hue,
        name: "Hue Bridge",
        host: "10.0.0.220",
        credentials: %{"api_key" => "key"},
        import_complete: true,
        enabled: true
      })

    light_json = %{
      "source" => "hue",
      "source_id" => "light-1",
      "name" => "Desk Lamp",
      "classification" => "light",
      "room_source_id" => "room-1",
      "capabilities" => %{}
    }

    group_json = %{
      "source" => "hue",
      "source_id" => "group-1",
      "name" => "Office Group",
      "classification" => "group_room",
      "room_source_id" => "room-1",
      "capabilities" => %{}
    }

    light =
      %Light{}
      |> Light.changeset(%{
        name: "Desk Lamp",
        source: :hue,
        source_id: "light-1",
        bridge_id: bridge.id,
        metadata: %{},
        normalized_json: light_json
      })
      |> Repo.insert!()

    group =
      %Group{}
      |> Group.changeset(%{
        name: "Office Group",
        source: :hue,
        source_id: "group-1",
        bridge_id: bridge.id,
        metadata: %{},
        normalized_json: group_json
      })
      |> Repo.insert!()

    %GroupLight{}
    |> GroupLight.changeset(%{group_id: group.id, light_id: light.id})
    |> Repo.insert!()

    normalized = NormalizeFromDb.normalize(bridge)

    assert Enum.any?(normalized.lights, &(&1["source_id"] == "light-1"))
    assert Enum.any?(normalized.groups, &(&1["source_id"] == "group-1"))
    assert normalized.rooms == []
    assert normalized.memberships.group_lights == [
             %{group_source_id: "group-1", light_source_id: "light-1"}
           ]
  end
end
