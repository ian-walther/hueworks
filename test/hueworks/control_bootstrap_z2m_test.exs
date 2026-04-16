defmodule Hueworks.Control.Bootstrap.Z2MTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Bootstrap.Z2M
  alias Hueworks.Control.State
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light, Room}

  setup do
    original_tortoise = Application.get_env(:hueworks, :z2m_bootstrap_tortoise_module)

    original_supervisor =
      Application.get_env(:hueworks, :z2m_bootstrap_tortoise_supervisor_module)

    original_connection =
      Application.get_env(:hueworks, :z2m_bootstrap_tortoise_connection_module)

    original_sink = Application.get_env(:hueworks, :z2m_bootstrap_test_sink)

    Application.put_env(:hueworks, :z2m_bootstrap_tortoise_module, __MODULE__.TortoiseStub)

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_supervisor_module,
      __MODULE__.SupervisorStub
    )

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_connection_module,
      __MODULE__.ConnectionStub
    )

    Application.put_env(:hueworks, :z2m_bootstrap_test_sink, self())

    if :ets.whereis(:hueworks_control_state) != :undefined do
      :ets.delete_all_objects(:hueworks_control_state)
    end

    on_exit(fn ->
      Application.put_env(:hueworks, :z2m_bootstrap_tortoise_module, original_tortoise)

      Application.put_env(
        :hueworks,
        :z2m_bootstrap_tortoise_supervisor_module,
        original_supervisor
      )

      Application.put_env(
        :hueworks,
        :z2m_bootstrap_tortoise_connection_module,
        original_connection
      )

      Application.put_env(:hueworks, :z2m_bootstrap_test_sink, original_sink)
    end)

    :ok
  end

  test "bootstrap requests current z2m states and seeds control state" do
    room = Repo.insert!(%Room{name: "Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M",
        host: "10.0.0.80",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    light =
      Repo.insert!(%Light{
        name: "Kitchen Strip",
        source: :z2m,
        source_id: "kitchen_strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Kitchen Group",
        source: :z2m,
        source_id: "kitchen_group",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        metadata: %{"members" => ["kitchen_strip"]}
      })

    assert :ok == Z2M.run()

    assert_receive {:publish, client_id_a, topic_a, _payload_a, [qos: 0]}
    assert_receive {:publish, client_id_b, topic_b, _payload_b, [qos: 0]}

    assert client_id_a == client_id_b
    assert String.starts_with?(client_id_a, "hwz2mb#{bridge.id}_")

    assert Enum.sort([topic_a, topic_b]) == [
             "zigbee2mqtt/kitchen_group/get",
             "zigbee2mqtt/kitchen_strip/get"
           ]

    assert %{power: :off} = State.get(:light, light.id)
    assert %{power: :off} = State.get(:group, group.id)
  end

  test "bootstrap requests full light state fields for temp-capable z2m entities" do
    room = Repo.insert!(%Room{name: "Request Fields"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M Request Fields",
        host: "10.0.0.82",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    _light =
      Repo.insert!(%Light{
        name: "Field Strip",
        source: :z2m,
        source_id: "field_strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    assert :ok == Z2M.run()

    assert_receive {:publish, _client_id, "zigbee2mqtt/field_strip/get", payload, [qos: 0]}

    assert Jason.decode!(payload) == %{
             "state" => "",
             "brightness" => "",
             "color_temp" => "",
             "color_mode" => "",
             "color" => ""
           }
  end

  test "bootstrap waits for subscription confirmation before requesting entity states" do
    original_supervisor =
      Application.get_env(:hueworks, :z2m_bootstrap_tortoise_supervisor_module)

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_supervisor_module,
      __MODULE__.DelayedSubscriptionSupervisorStub
    )

    room = Repo.insert!(%Room{name: "Delayed Kitchen"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M Delayed",
        host: "10.0.0.81",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    _light =
      Repo.insert!(%Light{
        name: "Delayed Strip",
        source: :z2m,
        source_id: "delayed_strip",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    task = Task.async(fn -> Z2M.run() end)

    refute_receive {:publish, _, _, _, _}, 20
    assert_receive {:subscription_ready, {"zigbee2mqtt/#", 0}}, 200
    assert_receive {:publish, client_id, "zigbee2mqtt/delayed_strip/get", _payload, [qos: 0]}, 200
    assert String.starts_with?(client_id, "hwz2mb#{bridge.id}_")
    assert :ok == Task.await(task, 500)

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_supervisor_module,
      original_supervisor
    )
  end

  test "bootstrap keeps individual member states when group state arrives later" do
    original_supervisor =
      Application.get_env(:hueworks, :z2m_bootstrap_tortoise_supervisor_module)

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_supervisor_module,
      __MODULE__.DivergedMemberSupervisorStub
    )

    on_exit(fn ->
      Application.put_env(
        :hueworks,
        :z2m_bootstrap_tortoise_supervisor_module,
        original_supervisor
      )
    end)

    room = Repo.insert!(%Room{name: "Bar"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M Diverged",
        host: "10.0.0.83",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    lower =
      Repo.insert!(%Light{
        name: "Bar Lower Cabinet Lights",
        source: :z2m,
        source_id: "bar_lower_cabinet",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    upper =
      Repo.insert!(%Light{
        name: "Bar Upper Cabinet Lights",
        source: :z2m,
        source_id: "bar_upper_cabinet",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group =
      Repo.insert!(%Group{
        name: "Bar Cabinet Lights",
        source: :z2m,
        source_id: "bar_cabinet_group",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500,
        metadata: %{"members" => ["bar_lower_cabinet", "bar_upper_cabinet"]}
      })

    assert :ok == Z2M.run()

    assert %{power: :on, brightness: 69, kelvin: 2000} = State.get(:group, group.id)
    assert %{power: :on, brightness: 69, kelvin: 2000} = State.get(:light, lower.id)
    assert %{power: :off} = State.get(:light, upper.id)
  end

  test "bootstrap recomputes group kelvin from mapped member states" do
    original_supervisor =
      Application.get_env(:hueworks, :z2m_bootstrap_tortoise_supervisor_module)

    Application.put_env(
      :hueworks,
      :z2m_bootstrap_tortoise_supervisor_module,
      __MODULE__.MappedKelvinSupervisorStub
    )

    on_exit(fn ->
      Application.put_env(
        :hueworks,
        :z2m_bootstrap_tortoise_supervisor_module,
        original_supervisor
      )
    end)

    room = Repo.insert!(%Room{name: "Mapped Bar"})

    bridge =
      insert_bridge!(%{
        type: :z2m,
        name: "Z2M Mapped",
        host: "10.0.0.84",
        credentials: %{"base_topic" => "zigbee2mqtt", "broker_port" => 1883},
        enabled: true
      })

    lower =
      Repo.insert!(%Light{
        name: "Mapped Lower Cabinet",
        source: :z2m,
        source_id: "mapped_lower_cabinet",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6329,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    upper =
      Repo.insert!(%Light{
        name: "Mapped Upper Cabinet",
        source: :z2m,
        source_id: "mapped_upper_cabinet",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6329,
        actual_min_kelvin: 2700,
        actual_max_kelvin: 6500,
        extended_kelvin_range: true
      })

    group =
      Repo.insert!(%Group{
        name: "Mapped Cabinet Group",
        source: :z2m,
        source_id: "mapped_cabinet_group",
        bridge_id: bridge.id,
        room_id: room.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6329,
        metadata: %{"members" => ["mapped_lower_cabinet", "mapped_upper_cabinet"]}
      })

    assert :ok == Z2M.run()

    assert State.get(:light, lower.id) == %{power: :on, kelvin: 3043}
    assert State.get(:light, upper.id) == %{power: :on, kelvin: 3043}
    assert State.get(:group, group.id) == %{power: :on, kelvin: 3043}
  end

  defmodule TortoiseStub do
    def publish(client_id, topic, payload, opts) do
      send(
        Application.fetch_env!(:hueworks, :z2m_bootstrap_test_sink),
        {:publish, client_id, topic, payload, opts}
      )

      :ok
    end
  end

  defmodule SupervisorStub do
    def start_child(opts) do
      {handler_module, [owner]} = Keyword.fetch!(opts, :handler)
      sink = Application.fetch_env!(:hueworks, :z2m_bootstrap_test_sink)
      subscriptions = Keyword.fetch!(opts, :subscriptions)
      send(sink, {:start_child, opts})

      worker =
        spawn(fn ->
          {:ok, handler_state} = handler_module.init([owner])
          [{topic_filter, _qos}] = subscriptions
          {:ok, _handler_state} = handler_module.subscription(:up, topic_filter, handler_state)

          Process.sleep(10)

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "kitchen_strip"],
             Jason.encode!(%{"state" => "OFF"})}
          )

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "kitchen_group"],
             Jason.encode!(%{"state" => "OFF"})}
          )

          Process.sleep(:infinity)
        end)

      {:ok, worker}
    end
  end

  defmodule ConnectionStub do
    def connection(_client_id, _opts), do: {:ok, {:tcp, :socket}}
  end

  defmodule DelayedSubscriptionSupervisorStub do
    def start_child(opts) do
      {handler_module, [owner]} = Keyword.fetch!(opts, :handler)
      sink = Application.fetch_env!(:hueworks, :z2m_bootstrap_test_sink)
      subscriptions = Keyword.fetch!(opts, :subscriptions)
      send(sink, {:start_child, opts})

      worker =
        spawn(fn ->
          {:ok, handler_state} = handler_module.init([owner])
          Process.sleep(50)
          [{topic_filter, _qos}] = subscriptions
          send(sink, {:subscription_ready, {topic_filter, 0}})
          {:ok, _handler_state} = handler_module.subscription(:up, topic_filter, handler_state)

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "delayed_strip"],
             Jason.encode!(%{"state" => "OFF"})}
          )

          Process.sleep(:infinity)
        end)

      {:ok, worker}
    end
  end

  defmodule MappedKelvinSupervisorStub do
    def start_child(opts) do
      {handler_module, [owner]} = Keyword.fetch!(opts, :handler)
      sink = Application.fetch_env!(:hueworks, :z2m_bootstrap_test_sink)
      subscriptions = Keyword.fetch!(opts, :subscriptions)
      send(sink, {:start_child, opts})

      worker =
        spawn(fn ->
          {:ok, handler_state} = handler_module.init([owner])
          [{topic_filter, _qos}] = subscriptions
          {:ok, _handler_state} = handler_module.subscription(:up, topic_filter, handler_state)

          payload =
            Jason.encode!(%{
              "state" => "ON",
              "color_mode" => "color_temp",
              "color_temp" => 434
            })

          send(owner, {:z2m_bootstrap_msg, ["zigbee2mqtt", "mapped_lower_cabinet"], payload})
          send(owner, {:z2m_bootstrap_msg, ["zigbee2mqtt", "mapped_upper_cabinet"], payload})
          send(owner, {:z2m_bootstrap_msg, ["zigbee2mqtt", "mapped_cabinet_group"], payload})

          Process.sleep(:infinity)
        end)

      {:ok, worker}
    end
  end

  defmodule DivergedMemberSupervisorStub do
    def start_child(opts) do
      {handler_module, [owner]} = Keyword.fetch!(opts, :handler)
      subscriptions = Keyword.fetch!(opts, :subscriptions)

      worker =
        spawn(fn ->
          {:ok, handler_state} = handler_module.init([owner])
          [{topic_filter, _qos}] = subscriptions
          {:ok, _handler_state} = handler_module.subscription(:up, topic_filter, handler_state)

          Process.sleep(10)

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "bar_lower_cabinet"],
             Jason.encode!(%{
               "state" => "ON",
               "brightness_percent" => 69,
               "color_temp_kelvin" => 2000
             })}
          )

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "bar_upper_cabinet"],
             Jason.encode!(%{"state" => "OFF"})}
          )

          send(
            owner,
            {:z2m_bootstrap_msg, ["zigbee2mqtt", "bar_cabinet_group"],
             Jason.encode!(%{
               "state" => "ON",
               "brightness_percent" => 69,
               "color_temp_kelvin" => 2000
             })}
          )

          Process.sleep(:infinity)
        end)

      {:ok, worker}
    end
  end
end
