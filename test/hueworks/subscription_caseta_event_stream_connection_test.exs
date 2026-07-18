defmodule Hueworks.Subscription.CasetaEventStream.ConnectionTest do
  use Hueworks.DataCase, async: false

  import ExUnit.CaptureLog

  alias Hueworks.Control.State
  alias Hueworks.Control.DesiredState
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Light, PicoButton, PicoDevice, Area}
  alias Hueworks.Subscription.CasetaEventStream.Connection

  defp insert_pico_button(attrs) do
    %PicoButton{}
    |> PicoButton.changeset(attrs)
    |> Repo.insert!()
  end

  setup do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    :ok
  end

  test "zone status frames update mapped Caseta lights" do
    area = Repo.insert!(%Area{name: "Living"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.90",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "42",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    state = %{
      bridge: bridge,
      lights: %{light.source_id => light.id},
      buffer: ""
    }

    payload = %{
      "Body" => %{
        "ZoneStatus" => %{
          "Zone" => %{"href" => "/zone/42"},
          "Level" => 75
        }
      }
    }

    assert {:noreply, ^state} = Connection.handle_frame(Jason.encode!(payload), state)
    assert State.get(:light, light.id) == %{power: :on, brightness: 75}
  end

  test "init defers Caseta LEAP connect to handle_continue" do
    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.96",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    parent = self()

    connect_fun = fn _bridge ->
      send(parent, :connect_attempted)
      {:error, :boom}
    end

    assert {:ok, state, {:continue, :connect}} =
             Connection.init({bridge, connect_fun: connect_fun})

    assert state.bridge.id == bridge.id
    assert state.lights == %{}
    assert state.pico_button_ids == []
    refute_receive :connect_attempted, 25
  end

  test "start_link rejects missing Caseta credentials before starting a process" do
    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.97",
        credentials: %{},
        enabled: true
      })

    assert {:error, :missing_credentials} = Connection.start_link(bridge)
  end

  test "unknown zone status refreshes Caseta light index and applies immediately" do
    area = Repo.insert!(%Area{name: "Refresh Living"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.93",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    state = caseta_state(bridge)

    light =
      Repo.insert!(%Light{
        name: "New Lamp",
        source: :caseta,
        source_id: "72",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    payload = zone_status_payload("72", 64)

    assert {:noreply, refreshed_state} = Connection.handle_frame(Jason.encode!(payload), state)
    assert State.get(:light, light.id) == %{power: :on, brightness: 64}
    assert Map.fetch!(refreshed_state.lights, light.source_id) == light.id
  end

  test "unknown zone status refresh is rate limited" do
    area = Repo.insert!(%Area{name: "Refresh Limited Living"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.94",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    first =
      Repo.insert!(%Light{
        name: "First Lamp",
        source: :caseta,
        source_id: "82",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    state = caseta_state(bridge)

    assert {:noreply, refreshed_state} =
             Connection.handle_frame(Jason.encode!(zone_status_payload("82", 70)), state)

    assert State.get(:light, first.id) == %{power: :on, brightness: 70}

    second =
      Repo.insert!(%Light{
        name: "Second Lamp",
        source: :caseta,
        source_id: "83",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    assert {:noreply, ^refreshed_state} =
             Connection.handle_frame(
               Jason.encode!(zone_status_payload("83", 70)),
               refreshed_state
             )

    assert State.get(:light, second.id) == nil
  end

  test "button press frames trigger configured Pico button actions" do
    area = Repo.insert!(%Area{name: "Living"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.91",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        source: :caseta,
        source_id: "52",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        area_id: area.id,
        source_id: "device-1",
        name: "Living Pico",
        hardware_profile: "5_button"
      })

    _button =
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "1",
        button_number: 2,
        slot_index: 0,
        action_type: "turn_on",
        action_config: %{"light_ids" => [light.id]}
      })

    state = %{bridge: bridge, lights: %{}, pico_button_ids: ["1"], buffer: ""}

    button_payload = %{
      "Body" => %{
        "ButtonStatus" => %{
          "Button" => %{"href" => "/button/1"},
          "EventType" => "Press"
        }
      }
    }

    assert {:noreply, ^state} = Connection.handle_frame(Jason.encode!(button_payload), state)
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 100, kelvin: 3000}
    assert {:noreply, ^state} = Connection.handle_frame("{not-json", state)
  end

  test "nested button event frames trigger configured Pico button actions" do
    area = Repo.insert!(%Area{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.92",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Accent",
        source: :caseta,
        source_id: "62",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        area_id: area.id,
        source_id: "device-2",
        name: "Kitchen Accent Pico",
        hardware_profile: "5_button"
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "101",
      button_number: 2,
      slot_index: 0,
      action_type: "turn_on",
      action_config: %{"light_ids" => [light.id]}
    })

    state = %{bridge: bridge, lights: %{}, pico_button_ids: ["101"], buffer: ""}

    button_payload = %{
      "Header" => %{
        "Url" => "/button/101/status/event",
        "MessageBodyType" => "OneButtonStatusEvent"
      },
      "Body" => %{
        "ButtonStatus" => %{
          "Button" => %{"href" => "/button/101"},
          "ButtonEvent" => %{"EventType" => "Press"}
        }
      }
    }

    assert {:noreply, ^state} = Connection.handle_frame(Jason.encode!(button_payload), state)
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 100, kelvin: 3000}
  end

  test "unknown button events refresh Pico buttons and subscribe newly enabled buttons" do
    area = Repo.insert!(%Area{name: "Pico Refresh"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.95",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Pico Lamp",
        source: :caseta,
        source_id: "92",
        bridge_id: bridge.id,
        area_id: area.id,
        enabled: true
      })

    device =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        area_id: area.id,
        source_id: "device-refresh",
        name: "Refresh Pico",
        hardware_profile: "5_button"
      })

    insert_pico_button(%{
      pico_device_id: device.id,
      source_id: "202",
      button_number: 2,
      slot_index: 0,
      action_type: "turn_on",
      action_config: %{"light_ids" => [light.id]}
    })

    subscribe_fun = fn _socket, url -> send(self(), {:subscribed, url}) end
    state = caseta_state(bridge, %{socket: :fake_socket, subscribe_fun: subscribe_fun})

    button_payload = %{
      "Body" => %{
        "ButtonStatus" => %{
          "Button" => %{"href" => "/button/202"},
          "EventType" => "Press"
        }
      }
    }

    assert {:noreply, refreshed_state} =
             Connection.handle_frame(Jason.encode!(button_payload), state)

    assert refreshed_state.pico_button_ids == ["202"]
    assert_receive {:subscribed, "/button/202/status/event"}
    assert DesiredState.get(:light, light.id) == %{power: :on, brightness: 100, kelvin: 3000}
  end

  test "button handling errors do not crash the Caseta event stream" do
    area = Repo.insert!(%Area{name: "Bad Pico Config"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "10.0.0.98",
        credentials: %{
          "cert_path" => "/credentials/caseta.crt",
          "key_path" => "/credentials/caseta.key",
          "cacert_path" => "/credentials/caseta-ca.crt"
        },
        enabled: true
      })

    device_a =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        area_id: area.id,
        source_id: "device-bad-a",
        name: "Bad Pico A",
        hardware_profile: "5_button"
      })

    device_b =
      Repo.insert!(%PicoDevice{
        bridge_id: bridge.id,
        area_id: area.id,
        source_id: "device-bad-b",
        name: "Bad Pico B",
        hardware_profile: "5_button"
      })

    for device <- [device_a, device_b] do
      insert_pico_button(%{
        pico_device_id: device.id,
        source_id: "303",
        button_number: 2,
        slot_index: 0,
        action_type: "turn_on",
        action_config: %{"light_ids" => []}
      })
    end

    state = caseta_state(bridge, %{pico_button_ids: ["303"]})

    button_payload = %{
      "Body" => %{
        "ButtonStatus" => %{
          "Button" => %{"href" => "/button/303"},
          "EventType" => "Press"
        }
      }
    }

    assert capture_log(fn ->
             assert {:noreply, ^state} =
                      Connection.handle_frame(Jason.encode!(button_payload), state)
           end) =~ "caseta_button_event_failed"
  end

  defp caseta_state(bridge, attrs \\ %{}) do
    %{
      bridge: bridge,
      lights: %{},
      pico_button_ids: [],
      buffer: "",
      last_refresh_at: 0
    }
    |> Map.merge(attrs)
  end

  defp zone_status_payload(zone_id, level) do
    %{
      "Body" => %{
        "ZoneStatus" => %{
          "Zone" => %{"href" => "/zone/#{zone_id}"},
          "Level" => level
        }
      }
    }
  end
end
