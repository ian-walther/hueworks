defmodule Hueworks.Import.LinkTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.{Link, Materialize, Normalize}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Bridge, Group, GroupLight, Light}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  test "links HA lights and groups to canonical Hue/Caseta/Z2M entities" do
    hue_bridge = insert_bridge(:hue, "10.0.0.10")
    caseta_bridge = insert_bridge(:caseta, "10.0.0.11")
    z2m_bridge = insert_bridge(:z2m, "10.0.0.13")
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

    z2m_light =
      insert_light(z2m_bridge, %{
        source_id: "kitchen.strip",
        metadata: %{"identifiers" => %{"ieee" => "0x00124b0029abc001"}}
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

    ha_light_z2m =
      insert_light(ha_bridge, %{
        source_id: "light.z2m",
        metadata: %{"identifiers" => %{"ieee" => "0x00124b0029abc001"}}
      })

    hue_group = insert_group(hue_bridge, "group.hue")
    ha_group = insert_group(ha_bridge, "group.ha")

    insert_group_light(hue_group.id, hue_light.id)
    insert_group_light(ha_group.id, ha_light_hue.id)

    :ok = Link.apply()

    assert Repo.get(Light, ha_light_hue.id).canonical_light_id == hue_light.id
    assert Repo.get(Light, ha_light_caseta.id).canonical_light_id == caseta_light.id
    assert Repo.get(Light, ha_light_z2m.id).canonical_light_id == z2m_light.id
    assert Repo.get(Group, ha_group.id).canonical_group_id == hue_group.id
  end

  test "links HA Caseta lights normalized from lutron_caseta identifiers" do
    caseta_bridge = insert_bridge(:caseta, "10.0.0.21")
    ha_bridge = insert_bridge(:ha, "10.0.0.22")

    caseta_raw = %{
      "lights" => [
        %{
          "name" => "Kitchen / Pendants",
          "serial" => 12345678,
          "type" => "WallDimmer",
          "device_id" => "10",
          "zone_id" => "1",
          "model" => "PD-6WCL-XX",
          "area_id" => "area_1"
        }
      ],
      "groups" => []
    }

    ha_raw = %{
      "areas" => [],
      "device_registry" => [],
      "light_entities" => [
        %{
          "entity_id" => "light.kitchen_pendants",
          "platform" => "lutron_caseta",
          "source" => "lutron",
          "device_id" => "device-1",
          "name" => "Kitchen Pendants",
          "supported_color_modes" => ["brightness"],
          "device" => %{
            "id" => "device-1",
            "name" => "Kitchen Pendants",
            "identifiers" => [["lutron_caseta", "12345678"]],
            "connections" => []
          }
        }
      ],
      "group_entities" => [],
      "light_states" => %{},
      "zha_groups" => []
    }

    :ok = Materialize.materialize(caseta_bridge, Normalize.normalize(caseta_bridge, caseta_raw))
    :ok = Materialize.materialize(ha_bridge, Normalize.normalize(ha_bridge, ha_raw))
    :ok = Link.apply()

    caseta_light = Repo.get_by!(Light, bridge_id: caseta_bridge.id, source_id: "1")
    ha_light = Repo.get_by!(Light, bridge_id: ha_bridge.id, source_id: "light.kitchen_pendants")

    assert ha_light.canonical_light_id == caseta_light.id
  end

  test "does not arbitrarily link HA lights when multiple non-HA candidates share an identifier" do
    caseta_bridge = insert_bridge(:caseta, "10.0.0.31")
    ha_bridge = insert_bridge(:ha, "10.0.0.32")

    _first =
      insert_light(caseta_bridge, %{
        source_id: "1",
        metadata: %{"identifiers" => %{"serial" => "12345"}}
      })

    _second =
      insert_light(caseta_bridge, %{
        source_id: "2",
        metadata: %{"identifiers" => %{"serial" => "12345"}}
      })

    ha_light =
      insert_light(ha_bridge, %{
        source_id: "light.caseta_duplicate",
        metadata: %{"identifiers" => %{"serial" => "12345"}}
      })

    :ok = Link.apply()

    assert Repo.get(Light, ha_light.id).canonical_light_id == nil
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
