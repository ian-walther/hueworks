defmodule Hueworks.BridgeSeedsTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.BridgeSeeds
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  defp temp_json!(name, body) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{name}")
    File.write!(path, body)
    path
  end

  test "loads arbitrary bridge entries from secrets json" do
    path =
      temp_json!(
        "secrets.json",
        Jason.encode!(%{
          "bridges" => [
            %{
              "type" => "hue",
              "name" => "Upstairs",
              "host" => "192.168.1.10",
              "credentials" => %{"api_key" => "abc"}
            },
            %{
              "type" => "hue",
              "name" => "Downstairs",
              "host" => "192.168.1.11",
              "credentials" => %{"api_key" => "def"}
            },
            %{
              "type" => "z2m",
              "name" => "Z2M",
              "host" => "192.168.1.20",
              "credentials" => %{
                "broker_port" => 1884,
                "username" => "mqtt-user",
                "password" => "mqtt-pass",
                "base_topic" => "house/z2m"
              }
            }
          ]
        })
      )

    assert {:ok, bridges} = BridgeSeeds.load_from_file(path)
    assert length(bridges) == 3

    assert Enum.at(bridges, 0) == %{
             type: :hue,
             name: "Upstairs",
             host: "192.168.1.10",
             credentials: %{"api_key" => "abc"},
             enabled: true,
             import_complete: false
           }

    assert Enum.at(bridges, 2) == %{
             type: :z2m,
             name: "Z2M",
             host: "192.168.1.20",
             credentials: %{
               "broker_port" => 1884,
               "username" => "mqtt-user",
               "password" => "mqtt-pass",
               "base_topic" => "house/z2m"
             },
             enabled: true,
             import_complete: false
           }
  end

  test "seed_from_file upserts arbitrary bridge types including z2m" do
    path =
      temp_json!(
        "secrets.json",
        Jason.encode!(%{
          "bridges" => [
            %{
              "type" => "ha",
              "name" => "Home Assistant",
              "host" => "192.168.1.41",
              "credentials" => %{"token" => "token-1"}
            },
            %{
              "type" => "z2m",
              "name" => "Z2M Broker",
              "host" => "192.168.1.50",
              "credentials" => %{
                "broker_port" => 1883,
                "username" => "zigbee",
                "password" => "secret",
                "base_topic" => "zigbee2mqtt"
              }
            }
          ]
        })
      )

    assert {:ok, 2} = BridgeSeeds.seed_from_file(path)

    ha = Repo.get_by!(Bridge, type: :ha, host: "192.168.1.41")
    assert ha.name == "Home Assistant"
    assert ha.credentials.token == "token-1"

    z2m = Repo.get_by!(Bridge, type: :z2m, host: "192.168.1.50")
    assert z2m.name == "Z2M Broker"
    assert z2m.credentials.broker_port == 1883
    assert z2m.credentials.username == "zigbee"

    updated_path =
      temp_json!(
        "secrets-updated.json",
        Jason.encode!(%{
          "bridges" => [
            %{
              "type" => "ha",
              "name" => "HA Main",
              "host" => "192.168.1.41",
              "credentials" => %{"token" => "token-2"}
            }
          ]
        })
      )

    assert {:ok, 1} = BridgeSeeds.seed_from_file(updated_path)

    updated = Repo.get_by!(Bridge, type: :ha, host: "192.168.1.41")
    assert updated.name == "HA Main"
    assert updated.credentials.token == "token-2"
  end

  test "load_from_file returns descriptive error for invalid root shape" do
    path = temp_json!("bad-secrets.json", Jason.encode!(%{"not_bridges" => []}))

    assert {:error, {:invalid_shape, _message}} = BridgeSeeds.load_from_file(path)
  end
end
