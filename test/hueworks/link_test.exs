defmodule Hueworks.Import.LinkTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Link
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "links HA lights and groups to canonical Hue/Caseta entities" do
    hue_bridge = insert_bridge(:hue, "10.0.0.10")
    caseta_bridge = insert_bridge(:caseta, "10.0.0.11")
    ha_bridge = insert_bridge(:ha, "10.0.0.12")

    hue_light =
      insert_light(hue_bridge, %{
        source_id: "1",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    caseta_light =
      insert_light(caseta_bridge, %{
        source_id: "2",
        metadata: %{"identifiers" => %{"serial" => "12345"}}
      })

    ha_light_hue =
      insert_light(ha_bridge, %{
        source_id: "light.hue",
        metadata: %{"identifiers" => %{"mac" => "aa:bb:cc"}}
      })

    ha_light_caseta =
      insert_light(ha_bridge, %{
        source_id: "light.caseta",
        metadata: %{"identifiers" => %{"serial" => "12345"}}
      })

    hue_group = insert_group(hue_bridge, "group.hue")
    ha_group = insert_group(ha_bridge, "group.ha")

    insert_group_light(hue_group.id, hue_light.id)
    insert_group_light(ha_group.id, ha_light_hue.id)

    :ok = Link.apply()

    assert Repo.get(Light, ha_light_hue.id).canonical_light_id == hue_light.id
    assert Repo.get(Light, ha_light_caseta.id).canonical_light_id == caseta_light.id
    assert Repo.get(Group, ha_group.id).canonical_group_id == hue_group.id
  end

  defp insert_bridge(type, host) do
    %Bridge{}
    |> Bridge.changeset(%{
      type: type,
      name: "#{type} bridge",
      host: host,
      credentials: %{},
      import_complete: false,
      enabled: true
    })
    |> Repo.insert!()
  end

  defp insert_light(bridge, attrs) do
    base = %{
      name: "Light",
      source: bridge.type,
      source_id: attrs[:source_id],
      bridge_id: bridge.id,
      metadata: Map.get(attrs, :metadata, %{})
    }

    %Light{}
    |> Light.changeset(Map.merge(base, Map.drop(attrs, [:source_id, :metadata])))
    |> Repo.insert!()
  end

  defp insert_group(bridge, source_id) do
    %Group{}
    |> Group.changeset(%{
      name: "Group",
      source: bridge.type,
      source_id: source_id,
      bridge_id: bridge.id
    })
    |> Repo.insert!()
  end

  defp insert_group_light(group_id, light_id) do
    %GroupLight{}
    |> GroupLight.changeset(%{group_id: group_id, light_id: light_id})
    |> Repo.insert!()
  end
end
