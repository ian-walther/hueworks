defmodule Hueworks.Import.Fetch.HomeAssistantTest do
  use ExUnit.Case, async: false

  alias Hueworks.Import.Fetch.HomeAssistant
  alias Hueworks.Schemas.Bridge

  defmodule ClientStub do
    def connect(host, token) do
      Agent.start_link(fn -> %{host: host, token: token, requests: []} end)
    end

    def request(pid, type, _params) do
      Agent.update(pid, &update_in(&1.requests, fn requests -> requests ++ [type] end))

      case type do
        "config/entity_registry/list" ->
          {:ok,
           [
             %{
               "entity_id" => "light.office",
               "platform" => "hue",
               "device_id" => "device-1",
               "area_id" => "entity-area",
               "config_entry_id" => "hue-entry",
               "unique_id" => "unique"
             }
           ]}

        "config/device_registry/list" ->
          {:ok,
           [
             %{
               "id" => "device-1",
               "area_id" => "device-area",
               "identifiers" => [["hue", "device"]],
               "connections" => []
             }
           ]}

        "config/area_registry/list" ->
          {:ok, [%{"area_id" => "entity-area", "name" => "Office", "floor_id" => "main"}]}

        "config/floor_registry/list" ->
          {:ok, [%{"floor_id" => "main", "name" => "Main Floor"}]}

        "config_entries/get" ->
          {:ok, [%{"entry_id" => "hue-entry", "domain" => "hue", "title" => "Hue"}]}

        "get_states" ->
          {:ok,
           [
             %{
               "entity_id" => "light.office",
               "state" => "on",
               "attributes" => %{"supported_color_modes" => ["brightness"]}
             }
           ]}

        "zha/groups" ->
          {:error, :unsupported}
      end
    end
  end

  setup do
    original = Application.get_env(:hueworks, :ha_import_client)
    Application.put_env(:hueworks, :ha_import_client, ClientStub)

    on_exit(fn ->
      if original do
        Application.put_env(:hueworks, :ha_import_client, original)
      else
        Application.delete_env(:hueworks, :ha_import_client)
      end
    end)
  end

  test "fetches HA integration and spatial inventory without materializing entities" do
    bridge = %Bridge{
      id: 1,
      type: :ha,
      name: "Home Assistant",
      host: "ha.home:8123",
      credentials: %Bridge.Credentials{token: "token"}
    }

    raw = HomeAssistant.fetch_for_bridge(bridge)

    assert raw.floors == [%{"floor_id" => "main", "name" => "Main Floor"}]

    assert raw.config_entries == [
             %{"entry_id" => "hue-entry", "domain" => "hue", "title" => "Hue"}
           ]

    assert [%{entity_id: "light.office"} = light] = raw.light_entities
    assert light.area_id == "entity-area"
    assert light.config_entry_id == "hue-entry"
    assert raw.entity_registry != []
  end
end
