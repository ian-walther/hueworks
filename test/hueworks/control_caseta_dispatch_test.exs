defmodule Hueworks.Control.CasetaDispatchTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{
    DesiredState,
    DispatchReceipt,
    Executor,
    Light,
    Operation,
    Planner,
    State,
    TransitionPolicy
  }

  alias Hueworks.Repo
  alias Hueworks.Schemas.Area
  alias Hueworks.Schemas.Light, as: LightSchema

  setup do
    previous_ssl = Application.get_env(:hueworks, :caseta_client_ssl_module)
    previous_receiver = Application.get_env(:hueworks, :caseta_test_receiver)
    Application.put_env(:hueworks, :caseta_client_ssl_module, __MODULE__.SSLStub)
    Application.put_env(:hueworks, :caseta_test_receiver, self())

    on_exit(fn ->
      restore_app_env(:hueworks, :caseta_client_ssl_module, previous_ssl)
      restore_app_env(:hueworks, :caseta_test_receiver, previous_receiver)
    end)

    area = Repo.insert!(%Area{name: "Powder Room"})

    bridge =
      insert_bridge!(%{
        type: :caseta,
        name: "Caseta",
        host: "127.0.0.1",
        credentials: %{
          "cert_path" => "/nonexistent/client.crt",
          "key_path" => "/nonexistent/client.key",
          "cacert_path" => "/nonexistent/caseta.crt"
        },
        enabled: true
      })

    light =
      Repo.insert!(%LightSchema{
        name: "Vanity Lights",
        source: :caseta,
        source_id: "22",
        bridge_id: bridge.id,
        area_id: area.id,
        metadata: %{"type" => "WallDimmer", "model" => "PD-6WCL"}
      })

    %{area: area, light: light}
  end

  test "sends an explicit Caseta dimmer fade and reports the encoded duration", %{light: light} do
    receipt = Light.dispatch_state(light, %{power: :on, brightness: 40}, %{transition_ms: 3_750})

    assert_receive {:caseta_request,
                    %{
                      "CommuniqueType" => "CreateRequest",
                      "Header" => %{"Url" => "/zone/22/commandprocessor"},
                      "Body" => %{
                        "Command" => %{
                          "CommandType" => "GoToDimmedLevel",
                          "DimmedLevelParameters" => %{"Level" => 40, "FadeTime" => "00:00:04"}
                        }
                      }
                    }}

    assert {:ok, %DispatchReceipt{effective_transition_ms: 4_000}} = receipt
  end

  test "power-on without brightness fades to full and power-off fades to zero", %{light: light} do
    for {desired, level} <- [{%{power: :on}, 100}, {%{power: :off, brightness: 60}, 0}] do
      assert {:ok, %DispatchReceipt{effective_transition_ms: 1_000}} =
               Light.dispatch_state(light, desired, transition_ms: 1_000)

      assert received_command() == %{
               "CommandType" => "GoToDimmedLevel",
               "DimmedLevelParameters" => %{"Level" => level, "FadeTime" => "00:00:01"}
             }
    end
  end

  test "brightness-only fades round across minute boundaries", %{light: light} do
    assert {:ok, %DispatchReceipt{effective_transition_ms: 60_000}} =
             Light.dispatch_state(light, %{brightness: 48.7}, %{transition_ms: 59_500})

    assert received_command() == %{
             "CommandType" => "GoToDimmedLevel",
             "DimmedLevelParameters" => %{"Level" => 49, "FadeTime" => "00:01:00"}
           }
  end

  test "missing and zero durations use the ordinary level command", %{light: light} do
    for opts <- [%{}, %{transition_ms: 0}] do
      assert {:ok, %DispatchReceipt{effective_transition_ms: 0}} =
               Light.dispatch_state(light, %{brightness: 35}, opts)

      assert received_command() == %{
               "CommandType" => "GoToLevel",
               "Parameter" => [%{"Type" => "Level", "Value" => 35}]
             }
    end
  end

  test "positive fades round to whole seconds with a one-second minimum", %{light: light} do
    for {requested_ms, seconds} <- [{1, 1}, {500, 1}, {999, 1}, {1_499, 1}, {1_500, 2}] do
      encoded_ms = seconds * 1_000

      assert {:ok, %DispatchReceipt{effective_transition_ms: ^encoded_ms}} =
               Light.dispatch_state(light, %{brightness: 35}, %{transition_ms: requested_ms})

      assert received_command() == %{
               "CommandType" => "GoToDimmedLevel",
               "DimmedLevelParameters" => %{"Level" => 35, "FadeTime" => "00:00:0#{seconds}"}
             }
    end
  end

  test "switches keep binary levels even when a fade is requested", %{light: light} do
    switch = %{light | metadata: %{"type" => "WallSwitch"}}

    for {brightness, level} <- [{30, 100}, {0, 0}] do
      assert {:ok, %DispatchReceipt{effective_transition_ms: 0}} =
               Light.dispatch_state(switch, %{brightness: brightness}, %{transition_ms: 3_000})

      assert received_command() == %{
               "CommandType" => "GoToLevel",
               "Parameter" => [%{"Type" => "Level", "Value" => level}]
             }
    end
  end

  test "fades require a recognized LEAP dimmer type", %{light: light} do
    for type <- [nil, "UnknownDimmer", "CasetaFanSpeedController", "WhiteTune"] do
      light = %{light | metadata: %{"type" => type}}

      assert {:ok, %DispatchReceipt{effective_transition_ms: 0}} =
               Light.dispatch_state(light, %{power: :on}, %{transition_ms: 3_000})

      assert received_command() == %{
               "CommandType" => "GoToLevel",
               "Parameter" => [%{"Type" => "Level", "Value" => 100}]
             }
    end
  end

  test "a rejected fade returns the bridge error without sending a fallback", %{light: light} do
    Process.put(:caseta_response_status, "400 Bad Request")

    assert {:error, {:http_error, "400 Bad Request", _response}} =
             Light.dispatch_state(light, %{power: :off}, %{transition_ms: 3_000})

    assert %{"CommandType" => "GoToDimmedLevel"} = received_command()
    refute_received {:caseta_request, _payload}
  end

  test "executor waits for a scaled presence fade rounded up to one second", %{
    area: area,
    light: light
  } do
    previous_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    Application.put_env(:hueworks, :control_executor_enabled, true)
    on_exit(fn -> restore_app_env(:hueworks, :control_executor_enabled, previous_enabled) end)

    clock = start_supervised!({Agent, fn -> 0 end})

    executor =
      start_supervised!(
        {Executor,
         name: :executor_caseta_fade, now_fn: fn :millisecond -> Agent.get(clock, & &1) end}
      )

    desired = %{power: :on, brightness: 50}
    DesiredState.put(:light, light.id, desired)
    State.put(:light, light.id, %{power: :off, brightness: 1})

    operation =
      Operation.new(
        origin: :presence,
        transition_policy: TransitionPolicy.new(500, :brightness_delta)
      )

    plan = Planner.plan_area(area.id, %{{:light, light.id} => desired}, operation: operation)
    assert [%{apply_opts: %{transition_ms: 245}}] = plan
    assert :ok = Executor.enqueue(plan, server: executor)
    Executor.tick(executor, force: true)

    assert received_command() == %{
             "CommandType" => "GoToDimmedLevel",
             "DimmedLevelParameters" => %{"Level" => 50, "FadeTime" => "00:00:01"}
           }

    assert %{settle_at: 1_000, dispatch_id: dispatch_id} =
             :sys.get_state(executor).settlements[{:light, light.id}]

    State.put(:light, light.id, %{power: :on, brightness: 30})
    Agent.update(clock, fn _ -> 999 end)
    send(executor, {:verify_settlement, dispatch_id})

    assert Executor.stats(executor).settlements == 1
    assert %{had_work: false, has_pending: false} = Executor.tick(executor, force: true)
    refute_received {:caseta_request, _payload}

    State.put(:light, light.id, desired)
    Agent.update(clock, fn _ -> 1_000 end)
    send(executor, {:verify_settlement, dispatch_id})

    assert Executor.stats(executor).settlements == 0
    assert %{had_work: false, has_pending: false} = Executor.tick(executor, force: true)
    refute_received {:caseta_request, _payload}
  end

  test "empty desired state does not open a Caseta connection", %{light: light} do
    assert :ok = Light.dispatch_state(light, %{}, %{transition_ms: 3_000})
    refute_received :caseta_connected
  end

  defp received_command do
    assert_received {:caseta_request, %{"Body" => %{"Command" => command}}}
    command
  end

  defmodule SSLStub do
    def connect(_host, 8081, _opts, _timeout) do
      receiver = Application.fetch_env!(:hueworks, :caseta_test_receiver)
      Kernel.send(receiver, :caseta_connected)
      {:ok, receiver}
    end

    def setopts(_socket, _opts), do: :ok

    def send(receiver, request) do
      payload = Jason.decode!(request)
      Process.put(:caseta_response_url, get_in(payload, ["Header", "Url"]))
      Kernel.send(receiver, {:caseta_request, payload})
      :ok
    end

    def recv(_socket, 0, _timeout) do
      response = %{
        "Header" => %{
          "Url" => Process.get(:caseta_response_url),
          "StatusCode" => Process.get(:caseta_response_status, "201 Created")
        }
      }

      {:ok, Jason.encode!(response) <> "\r\n"}
    end

    def close(_socket), do: :ok
  end
end
