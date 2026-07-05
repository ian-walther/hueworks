defmodule Hueworks.Subscription.HomeAssistantEventStream.ConnectionTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, HomeAssistantPayload, State}
  alias Hueworks.ActiveScenes
  alias Hueworks.Repo

  alias Hueworks.Schemas.{
    ActiveScene,
    Bridge,
    ExternalScene,
    ExternalSceneMapping,
    Group,
    Light,
    Room,
    Scene
  }

  alias Hueworks.Subscription.HomeAssistantEventStream.Connection

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    Process.register(self(), :ha_connection_test_listener)

    on_exit(fn ->
      if Process.whereis(:ha_connection_test_listener) == self() do
        Process.unregister(:ha_connection_test_listener)
      end
    end)

    :ok
  end

  defmodule FakeWebSockex do
    def start_link(url, module, state, opts) do
      listener = Process.whereis(:ha_connection_test_listener)
      if listener, do: send(listener, {:websockex_start_link, url, module, state, opts})
      {:ok, self()}
    end
  end

  test "event handler maps extended xy HA updates to low kelvin values" do
    room = Repo.insert!(%Room{name: "Living"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.80",
        credentials: %{"token" => "token"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Cabinet",
        source: :ha,
        source_id: "light.cabinet",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    {x, y} = HomeAssistantPayload.extended_xy(2000)

    state = %{
      bridge: bridge,
      token: "token",
      next_id: 1,
      pending_subscriptions: [],
      lights: %{light.source_id => light},
      groups: %{},
      group_members: %{}
    }

    payload = %{
      "type" => "event",
      "event" => %{
        "event_type" => "state_changed",
        "data" => %{
          "entity_id" => light.source_id,
          "new_state" => %{
            "state" => "on",
            "attributes" => %{
              "xy_color" => [x, y],
              "color_temp" => 437
            }
          }
        }
      }
    }

    assert {:ok, _state} = Connection.handle_frame({:text, Jason.encode!(payload)}, state)

    assert State.get(:light, light.id) == %{power: :on, kelvin: 2000}
  end

  test "start_link uses async websocket start and defers entity index loading" do
    room = Repo.insert!(%Room{name: "Async HA"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.86",
        credentials: %{"token" => "token"},
        enabled: true
      })

    _light =
      Repo.insert!(%Light{
        name: "Existing Lamp",
        source: :ha,
        source_id: "light.existing",
        bridge_id: bridge.id,
        room_id: room.id
      })

    assert {:ok, _pid} = Connection.start_link(bridge, FakeWebSockex)

    assert_receive {:websockex_start_link, "ws://10.0.0.86:8123/api/websocket", Connection, state,
                    opts}

    assert Keyword.fetch!(opts, :async) == true
    assert state.lights == %{}
    assert state.groups == %{}
    assert state.group_members == %{}
  end

  test "handle_connect loads HA entity indexes inside the connection process" do
    room = Repo.insert!(%Room{name: "Connected HA"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.87",
        credentials: %{"token" => "token"},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Connected Lamp",
        source: :ha,
        source_id: "light.connected",
        bridge_id: bridge.id,
        room_id: room.id
      })

    state = ha_state(bridge)

    assert {:ok, connected_state} = Connection.handle_connect(:conn, state)
    assert Map.fetch!(connected_state.lights, light.source_id).id == light.id
  end

  test "auth_required replies with auth payload and auth_ok subscribes to state_changed then call_service" do
    state = %{
      bridge: %Bridge{name: "HA", host: "10.0.0.80"},
      token: "token-123",
      next_id: 1,
      pending_subscriptions: ["state_changed", "call_service"],
      lights: %{},
      groups: %{},
      group_members: %{}
    }

    assert {:reply, {:text, auth_json}, ^state} =
             Connection.handle_frame({:text, Jason.encode!(%{"type" => "auth_required"})}, state)

    assert Jason.decode!(auth_json) == %{"type" => "auth", "access_token" => "token-123"}

    assert {:reply, {:text, subscribe_json}, state_changed_state} =
             Connection.handle_frame({:text, Jason.encode!(%{"type" => "auth_ok"})}, state)

    assert Jason.decode!(subscribe_json) == %{
             "id" => 1,
             "type" => "subscribe_events",
             "event_type" => "state_changed"
           }

    assert state_changed_state.pending_subscriptions == ["call_service"]
    assert state_changed_state.next_id == 2

    assert {:reply, {:text, call_service_json}, call_service_state} =
             Connection.handle_frame(
               {:text, Jason.encode!(%{"type" => "result", "success" => true})},
               state_changed_state
             )

    assert Jason.decode!(call_service_json) == %{
             "id" => 2,
             "type" => "subscribe_events",
             "event_type" => "call_service"
           }

    assert call_service_state.pending_subscriptions == []
    assert call_service_state.next_id == 3
  end

  test "state_changed refreshes indexes for newly imported HA lights and applies immediately" do
    room = Repo.insert!(%Room{name: "Refresh Room"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.84",
        credentials: %{"token" => "token"},
        enabled: true
      })

    state = ha_state(bridge)

    light =
      Repo.insert!(%Light{
        name: "New Lamp",
        source: :ha,
        source_id: "light.new_lamp",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    payload = state_changed_payload(light.source_id, %{"state" => "on", "attributes" => %{}})

    assert {:ok, refreshed_state} =
             Connection.handle_frame({:text, Jason.encode!(payload)}, state)

    assert State.get(:light, light.id) == %{power: :on}
    assert Map.fetch!(refreshed_state.lights, light.source_id).id == light.id
  end

  test "state_changed index refresh is rate limited for unknown HA entities" do
    room = Repo.insert!(%Room{name: "Refresh Limit Room"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.85",
        credentials: %{"token" => "token"},
        enabled: true
      })

    first =
      Repo.insert!(%Light{
        name: "First Lamp",
        source: :ha,
        source_id: "light.first_lamp",
        bridge_id: bridge.id,
        room_id: room.id
      })

    state = ha_state(bridge)

    first_payload =
      state_changed_payload(first.source_id, %{"state" => "on", "attributes" => %{}})

    assert {:ok, refreshed_state} =
             Connection.handle_frame({:text, Jason.encode!(first_payload)}, state)

    assert State.get(:light, first.id) == %{power: :on}

    second =
      Repo.insert!(%Light{
        name: "Second Lamp",
        source: :ha,
        source_id: "light.second_lamp",
        bridge_id: bridge.id,
        room_id: room.id
      })

    second_payload =
      state_changed_payload(second.source_id, %{"state" => "on", "attributes" => %{}})

    assert {:ok, ^refreshed_state} =
             Connection.handle_frame({:text, Jason.encode!(second_payload)}, refreshed_state)

    assert State.get(:light, second.id) == nil
  end

  test "state_changed group events fan out state to member lights" do
    room = Repo.insert!(%Room{name: "Living"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.81",
        credentials: %{"token" => "token"},
        enabled: true
      })

    light_a =
      Repo.insert!(%Light{
        name: "Lamp A",
        source: :ha,
        source_id: "light.a",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_b =
      Repo.insert!(%Light{
        name: "Lamp B",
        source: :ha,
        source_id: "light.b",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Living Group",
        source: :ha,
        source_id: "light.living_group",
        bridge_id: bridge.id,
        room_id: room.id,
        metadata: %{"members" => [light_a.source_id, light_b.source_id]}
      })

    state = %{
      bridge: bridge,
      token: "token",
      next_id: 1,
      pending_subscriptions: [],
      lights: %{light_a.source_id => light_a, light_b.source_id => light_b},
      groups: %{group.source_id => group},
      group_members: %{group.source_id => [light_a.id, light_b.id]}
    }

    payload = %{
      "type" => "event",
      "event" => %{
        "event_type" => "state_changed",
        "data" => %{
          "entity_id" => group.source_id,
          "new_state" => %{
            "state" => "on",
            "attributes" => %{
              "brightness" => 128,
              "color_temp" => 400
            }
          }
        }
      }
    }

    assert {:ok, ^state} = Connection.handle_frame({:text, Jason.encode!(payload)}, state)

    assert State.get(:group, group.id) == %{power: :on, brightness: 50, kelvin: 2500}
    assert State.get(:light, light_a.id) == %{power: :on, brightness: 50, kelvin: 2500}
    assert State.get(:light, light_b.id) == %{power: :on, brightness: 50, kelvin: 2500}
  end

  test "state_changed group events preserve explicit member power state during fan-out" do
    room = Repo.insert!(%Room{name: "Office"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.83",
        credentials: %{"token" => "token"},
        enabled: true
      })

    desired_off =
      Repo.insert!(%Light{
        name: "Desired Off Lamp",
        source: :ha,
        source_id: "light.desired_off",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    physically_off =
      Repo.insert!(%Light{
        name: "Physically Off Lamp",
        source: :ha,
        source_id: "light.physically_off",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    desired_on =
      Repo.insert!(%Light{
        name: "Desired On Lamp",
        source: :ha,
        source_id: "light.desired_on",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Office Group",
        source: :ha,
        source_id: "light.office_group",
        bridge_id: bridge.id,
        room_id: room.id,
        metadata: %{
          "members" => [
            desired_off.source_id,
            physically_off.source_id,
            desired_on.source_id
          ]
        }
      })

    _ = State.put(:light, desired_off.id, %{power: :on})
    _ = State.put(:light, physically_off.id, %{power: :off})
    _ = State.put(:light, desired_on.id, %{power: :off})
    _ = DesiredState.put(:light, desired_off.id, %{power: :off})
    _ = DesiredState.put(:light, desired_on.id, %{power: :on})

    state = %{
      bridge: bridge,
      token: "token",
      next_id: 1,
      pending_subscriptions: [],
      lights: %{
        desired_off.source_id => desired_off,
        physically_off.source_id => physically_off,
        desired_on.source_id => desired_on
      },
      groups: %{group.source_id => group},
      group_members: %{group.source_id => [desired_off.id, physically_off.id, desired_on.id]}
    }

    payload = %{
      "type" => "event",
      "event" => %{
        "event_type" => "state_changed",
        "data" => %{
          "entity_id" => group.source_id,
          "new_state" => %{
            "state" => "on",
            "attributes" => %{
              "brightness" => 128,
              "color_temp" => 400
            }
          }
        }
      }
    }

    assert {:ok, ^state} = Connection.handle_frame({:text, Jason.encode!(payload)}, state)

    assert State.get(:light, desired_off.id).power == :off
    assert State.get(:light, physically_off.id).power == :off
    assert State.get(:light, desired_on.id).power == :on
    assert State.get(:group, group.id) == %{power: :on, brightness: 50, kelvin: 2500}
  end

  test "invalid json frames are ignored" do
    state = %{
      bridge: %Bridge{name: "HA", host: "10.0.0.80"},
      token: "token",
      next_id: 1,
      pending_subscriptions: ["state_changed", "call_service"],
      lights: %{},
      groups: %{},
      group_members: %{}
    }

    assert {:ok, ^state} = Connection.handle_frame({:text, "{not-json"}, state)
  end

  test "call_service scene events activate mapped HueWorks scenes" do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :ha,
        name: "HA",
        host: "10.0.0.82",
        credentials: %{"token" => "token"},
        enabled: true
      })

    scene = Repo.insert!(%Scene{name: "Cooking", room_id: room.id, metadata: %{}})

    external_scene =
      Repo.insert!(%ExternalScene{
        bridge_id: bridge.id,
        source: :ha,
        source_id: "scene.cooking",
        name: "Cooking Trigger",
        enabled: true,
        metadata: %{}
      })

    Repo.insert!(%ExternalSceneMapping{
      external_scene_id: external_scene.id,
      scene_id: scene.id,
      enabled: true,
      metadata: %{}
    })

    state = %{
      bridge: bridge,
      token: "token",
      next_id: 1,
      pending_subscriptions: [],
      lights: %{},
      groups: %{},
      group_members: %{}
    }

    payload = %{
      "type" => "event",
      "event" => %{
        "event_type" => "call_service",
        "data" => %{
          "domain" => "scene",
          "service" => "turn_on",
          "service_data" => %{"entity_id" => "scene.cooking"}
        }
      }
    }

    assert {:ok, ^state} = Connection.handle_frame({:text, Jason.encode!(payload)}, state)
    assert %ActiveScene{scene_id: scene_id} = ActiveScenes.get_for_room(room.id)
    assert scene_id == scene.id
  end

  defp ha_state(bridge, attrs \\ %{}) do
    %{
      bridge: bridge,
      token: "token",
      next_id: 1,
      pending_subscriptions: [],
      lights: %{},
      groups: %{},
      group_members: %{},
      last_refresh_at: 0
    }
    |> Map.merge(attrs)
  end

  defp state_changed_payload(entity_id, new_state) do
    %{
      "type" => "event",
      "event" => %{
        "event_type" => "state_changed",
        "data" => %{
          "entity_id" => entity_id,
          "new_state" => new_state
        }
      }
    }
  end
end
