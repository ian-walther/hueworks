defmodule Hueworks.Import.SyncIntegrationTest do
  use Hueworks.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.Caseta
  alias Hueworks.Import.HomeAssistant
  alias Hueworks.Import.Hue
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Group
  alias Hueworks.Schemas.Light

  setup do
    Repo.insert!(%Bridge{type: :hue, name: "Hue Bridge", host: "10.0.0.2", credentials: %{}})
    Repo.insert!(%Bridge{type: :caseta, name: "Caseta Bridge", host: "10.0.0.3", credentials: %{}})
    Repo.insert!(%Bridge{type: :ha, name: "Home Assistant", host: "10.0.0.4", credentials: %{}})
    :ok
  end

  test "imports lights and groups across bridges and links canonical groups" do
    hue_export = %{
      "bridges" => [
        %{
          "name" => "Hue Bridge",
          "host" => "10.0.0.2",
          "lights" => %{
            "1" => %{
              "name" => "Kitchen A",
              "uniqueid" => "AA-0b",
              "mac" => "AA",
              "capabilities" => %{"control" => %{"ct" => %{"min" => 153, "max" => 500}}}
            },
            "2" => %{
              "name" => "Kitchen B",
              "uniqueid" => "BB-0b",
              "mac" => "BB"
            }
          },
          "groups" => %{
            "10" => %{
              "name" => "Kitchen",
              "type" => "Room",
              "lights" => ["1", "2"]
            }
          }
        }
      ]
    }

    caseta_export = %{
      "bridge_ip" => "10.0.0.3",
      "lights" => [
        %{
          "name" => "Porch",
          "zone_id" => "100",
          "serial" => 123_456
        }
      ]
    }

    ha_export = %{
      "host" => "10.0.0.4",
      "light_entities" => [
        %{
          "entity_id" => "light.kitchen_a",
          "name" => "Kitchen A",
          "unique_id" => "ha-aa",
          "platform" => "hue",
          "source" => "hue",
          "device_id" => "dev-aa",
          "device" => %{
            "id" => "dev-aa",
            "connections" => [["mac", "AA"]],
            "identifiers" => []
          }
        },
        %{
          "entity_id" => "light.kitchen_b",
          "name" => "Kitchen B",
          "unique_id" => "ha-bb",
          "platform" => "hue",
          "source" => "hue",
          "device_id" => "dev-bb",
          "device" => %{
            "id" => "dev-bb",
            "connections" => [["mac", "BB"]],
            "identifiers" => []
          }
        }
      ],
      "group_entities" => [
        %{
          "entity_id" => "light.kitchen",
          "name" => "Kitchen",
          "platform" => "group",
          "members" => ["light.kitchen_a", "light.kitchen_b"]
        }
      ]
    }

    Hue.import(hue_export)
    Caseta.import(caseta_export)
    HomeAssistant.import(ha_export)

    hue_group = Repo.get_by!(Group, source: :hue, source_id: "10")
    ha_group = Repo.get_by!(Group, source: :ha, source_id: "light.kitchen")

    ha_lights =
      Repo.all(from(l in Light, where: l.source == :ha, order_by: [asc: l.source_id]))

    assert length(ha_lights) == 2
    assert Enum.all?(ha_lights, & &1.canonical_light_id)
    assert ha_group.canonical_group_id == hue_group.id
  end
end
