defmodule Hueworks.Control.Bootstrap.ScopedTest do
  use Hueworks.DataCase, async: false

  alias __MODULE__.SSL
  alias Hueworks.Control.{Bootstrap, DesiredState, State}
  alias Hueworks.Schemas.{Group, Light}

  test "Hue snapshots are bridge-scoped, publish observations, and preserve desired state" do
    bridge = bridge(:hue)
    light = light(bridge, "1")
    other = light(bridge(:hue, "other.invalid"), "1")

    group =
      Repo.insert!(%Group{name: "Group", source: :hue, source_id: "5", bridge_id: bridge.id})

    Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
    desired = DesiredState.snapshot([{:light, light.id}])

    get = fn url, [], _ ->
      send(self(), {:get, url})

      if String.ends_with?(url, "/lights"),
        do: response(%{"1" => %{"state" => %{"on" => true, "bri" => 254}}}),
        else: response(%{"5" => %{"action" => %{"on" => false}}})
    end

    assert :ok = Bootstrap.Hue.run(bridge, http_get: get)
    id = light.id
    assert_receive {:control_state, :light, ^id, %{power: :on, brightness: 100}}
    assert %{power: :off} = State.get(:group, group.id)
    assert nil == State.get(:light, other.id)
    assert desired == DesiredState.snapshot([{:light, light.id}])
    assert_receive {:get, "http://unused.invalid/api/key/lights"}
    assert_receive {:get, "http://unused.invalid/api/key/groups"}
  end

  test "Hue grouped observations alone cannot populate an unreported member" do
    bridge = bridge(:hue)
    member = light(bridge, "1")

    group =
      Repo.insert!(%Group{name: "Group", source: :hue, source_id: "5", bridge_id: bridge.id})

    get = fn url, _, _ ->
      if String.ends_with?(url, "/lights"),
        do: response(%{}),
        else: response(%{"5" => %{"action" => %{"on" => true, "bri" => 254}}})
    end

    assert :ok = Bootstrap.Hue.run(bridge, http_get: get)
    assert %{brightness: 100} = State.get(:group, group.id)
    assert nil == State.get(:light, member.id)
  end

  test "a newer individual observation wins over a delayed Hue snapshot" do
    bridge = bridge(:hue)
    light = light(bridge, "1")
    State.put(:light, light.id, %{brightness: 10, power: :on})

    get = fn url, _, _ ->
      if String.ends_with?(url, "/lights") do
        State.put(:light, light.id, %{brightness: 80})
        response(%{"1" => %{"state" => %{"on" => false, "bri" => 127}}})
      else
        response(%{})
      end
    end

    assert :ok = Bootstrap.Hue.run(bridge, http_get: get)
    assert %{brightness: 80, power: :on} = State.get(:light, light.id)
  end

  test "failed and malformed Hue responses are retryable rather than successful empty snapshots" do
    bridge = bridge(:hue)
    light = light(bridge, "1")
    State.put(:light, light.id, %{brightness: 10})

    assert {:error, :request_failed} =
             Bootstrap.Hue.run(bridge, http_get: fn _, _, _ -> {:error, :timeout} end)

    for body <- ["not-json", "[]", "null"] do
      assert {:error, :invalid_response} =
               Bootstrap.Hue.run(bridge,
                 http_get: fn _, _, _ ->
                   {:ok, %HTTPoison.Response{status_code: 200, body: body}}
                 end
               )
    end

    assert %{brightness: 10} = State.get(:light, light.id)
  end

  test "HA snapshots refresh only the selected bridge and do not invent group member state" do
    bridge = bridge(:ha)
    light = light(bridge, "light.lamp")
    other = light(bridge(:ha, "other.invalid"), "light.lamp")
    member = light(bridge, "light.unreported")

    group =
      Repo.insert!(%Group{
        name: "Group",
        source: :ha,
        source_id: "light.group",
        bridge_id: bridge.id,
        metadata: %{"members" => ["light.unreported"]}
      })

    get = fn url, headers, _ ->
      assert url == "http://unused.invalid:8123/api/states"
      assert {"Authorization", "Bearer token"} in headers

      response([
        %{"entity_id" => "light.lamp", "state" => "on", "attributes" => %{"brightness" => 255}},
        %{"entity_id" => "light.group", "state" => "on", "attributes" => %{"brightness" => 255}}
      ])
    end

    assert :ok = Bootstrap.HomeAssistant.run(bridge, http_get: get)
    assert %{brightness: 100} = State.get(:light, light.id)
    assert %{brightness: 100} = State.get(:group, group.id)
    assert nil == State.get(:light, other.id)
    assert nil == State.get(:light, member.id)
  end

  test "HA preserves newer live observations and reports HTTP failures" do
    bridge = bridge(:ha)
    light = light(bridge, "light.lamp")

    get = fn _, _, _ ->
      State.put(:light, light.id, %{power: :on, brightness: 80})
      response([%{"entity_id" => "light.lamp", "state" => "off", "attributes" => %{}}])
    end

    assert :ok = Bootstrap.HomeAssistant.run(bridge, http_get: get)
    assert %{power: :on, brightness: 80} = State.get(:light, light.id)

    assert {:error, _} =
             Bootstrap.HomeAssistant.run(bridge,
               http_get: fn _, _, _ ->
                 {:ok, %HTTPoison.Response{status_code: 503, body: "offline"}}
               end
             )
  end

  test "Caseta hydration reads zone status, closes its socket, and is bridge-scoped" do
    bridge = bridge(:caseta)
    light = light(bridge, "1")
    other = light(bridge(:caseta, "other.invalid"), "1")
    Process.put(:ssl_response, fn -> caseta_response(45) end)
    assert :ok = Bootstrap.Caseta.run(bridge, ssl_module: SSL)

    assert_receive {:ssl_request,
                    %{"CommuniqueType" => "ReadRequest", "Header" => %{"Url" => "/zone/status"}}}

    assert_receive :ssl_closed
    assert %{power: :on, brightness: 45} = State.get(:light, light.id)
    assert nil == State.get(:light, other.id)
    refute_receive {:ssl_request, _}
  end

  test "Caseta preserves newer observations and closes on errors" do
    bridge = bridge(:caseta)
    light = light(bridge, "1")

    Process.put(:ssl_response, fn ->
      State.put(:light, light.id, %{brightness: 80})
      caseta_response(45)
    end)

    assert :ok = Bootstrap.Caseta.run(bridge, ssl_module: SSL)
    assert %{brightness: 80} = State.get(:light, light.id)
    assert_receive :ssl_closed
    Process.put(:ssl_response, fn -> {:error, :timeout} end)
    assert {:error, :timeout} = Bootstrap.Caseta.run(bridge, ssl_module: SSL)
    assert_receive :ssl_closed
  end

  test "all scoped hydration paths respect runtime-I/O-disabled mode" do
    bridges = Enum.map([:hue, :ha, :caseta, :z2m], &bridge/1)
    old = Application.get_env(:hueworks, :runtime_io_disabled)
    Application.put_env(:hueworks, :runtime_io_disabled, true)
    on_exit(fn -> restore_app_env(:hueworks, :runtime_io_disabled, old) end)

    for {bridge, module} <-
          Enum.zip(bridges, [
            Bootstrap.Hue,
            Bootstrap.HomeAssistant,
            Bootstrap.Caseta,
            Bootstrap.Z2M
          ]) do
      assert {:error, :runtime_io_disabled} = module.run(bridge)
    end
  end

  defp bridge(type, host \\ "unused.invalid") do
    credentials =
      case type do
        :hue ->
          %{"api_key" => "key"}

        :ha ->
          %{"token" => "token"}

        :caseta ->
          %{"cert_path" => "test-cert", "key_path" => "test-key", "cacert_path" => "test-ca"}

        :z2m ->
          %{"base_topic" => "z2m"}
      end

    insert_bridge!(%{type: type, name: "Bridge", host: host, credentials: credentials})
  end

  defp light(bridge, source_id) do
    Repo.insert!(%Light{
      name: "Light",
      source: bridge.type,
      source_id: source_id,
      bridge_id: bridge.id
    })
  end

  defp response(body), do: {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}

  defp caseta_response(level),
    do:
      {:ok,
       Jason.encode!(%{
         "Header" => %{"Url" => "/zone/status"},
         "Body" => %{"ZoneStatuses" => [%{"Zone" => %{"href" => "/zone/1"}, "Level" => level}]}
       }) <> "\r\n"}

  defmodule SSL do
    def connect(~c"unused.invalid", 8081, _, _), do: {:ok, :test_socket}
    def setopts(:test_socket, active: false, packet: :line), do: :ok

    def send(:test_socket, bytes) do
      Kernel.send(self(), {:ssl_request, Jason.decode!(String.trim(bytes))})
      :ok
    end

    def recv(:test_socket, 0, _), do: Process.get(:ssl_response).()
    def close(:test_socket), do: Kernel.send(self(), :ssl_closed)
  end
end
