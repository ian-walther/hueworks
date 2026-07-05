defmodule Hueworks.Control.Z2MConfigTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Z2MConfig
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Bridge.Credentials

  describe "for_bridge/1" do
    test "normalizes mqtt connection options from bridge credentials" do
      bridge =
        insert_bridge!(%{
          type: :z2m,
          name: "Z2M",
          host: "broker.local",
          credentials: %{
            "broker_port" => "1884",
            "base_topic" => "  house/zigbee  ",
            "username" => "  zigbee-user  ",
            "password" => "  secret  "
          }
        })

      assert Z2MConfig.for_bridge(bridge) == %{
               bridge_id: bridge.id,
               host: "broker.local",
               port: 1884,
               base_topic: "house/zigbee",
               username: "zigbee-user",
               password: "secret"
             }
    end

    test "uses z2m defaults for missing or invalid optional connection fields" do
      bridge = %Bridge{
        id: 123,
        type: :z2m,
        name: "Z2M",
        host: "broker.local",
        credentials: %Credentials{
          broker_port: 70_000,
          base_topic: nil,
          username: nil,
          password: nil
        }
      }

      assert Z2MConfig.for_bridge(bridge) == %{
               bridge_id: 123,
               host: "broker.local",
               port: 1883,
               base_topic: "zigbee2mqtt",
               username: nil,
               password: nil
             }
    end

    test "falls back to defaults when raw credentials cannot be loaded" do
      bridge = %Bridge{
        id: 456,
        type: :z2m,
        name: "Z2M",
        host: "broker.local",
        credentials: %{"broker_port" => "not-a-port", "base_topic" => "zigbee2mqtt"}
      }

      assert Z2MConfig.for_bridge(bridge) == %{
               bridge_id: 456,
               host: "broker.local",
               port: 1883,
               base_topic: "zigbee2mqtt",
               username: nil,
               password: nil
             }
    end

    test "normalizes blank optional fields from changeset-loaded credentials" do
      bridge =
        insert_bridge!(%{
          type: :z2m,
          name: "Z2M",
          host: "broker.local",
          credentials: %{
            "base_topic" => " ",
            "username" => " ",
            "password" => " "
          }
        })

      assert Z2MConfig.for_bridge(bridge) == %{
               bridge_id: bridge.id,
               host: "broker.local",
               port: 1883,
               base_topic: "zigbee2mqtt",
               username: nil,
               password: nil
             }
    end
  end

  describe "tortoise_auth_opts/1" do
    test "emits auth options only when a username is configured" do
      opts = Z2MConfig.tortoise_auth_opts(%{username: "user", password: "pass"})
      assert Keyword.get(opts, :user_name) == "user"
      assert Keyword.get(opts, :password) == "pass"

      assert Z2MConfig.tortoise_auth_opts(%{username: "user", password: nil}) == [
               user_name: "user"
             ]

      assert Z2MConfig.tortoise_auth_opts(%{username: nil, password: "pass"}) == []
    end
  end
end
