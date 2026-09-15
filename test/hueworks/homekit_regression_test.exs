defmodule Hueworks.HomeKitRegressionTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.{DesiredState, State}
  alias Hueworks.HomeKit.{Bridge, HAPSessionTransport, ValueStore, Writer}
  alias Hueworks.Schemas

  setup do
    :ok = Writer.discard_pending()

    env = [
      control_executor_enabled: false,
      homekit_write_coalesce_ms: 60_000,
      homekit_notify_debounce_ms: 0,
      homekit_value_cache_ttl_ms: 1_000,
      homekit_hap_module: __MODULE__.HAPStub,
      homekit_pairing_state_module: __MODULE__.PairedStub,
      homekit_notifier_module: __MODULE__.NotifierStub,
      homekit_regression_sink: self()
    ]

    originals =
      Map.new([:control_executor_server | Keyword.keys(env)], fn key ->
        {key, Application.fetch_env(:hueworks, key)}
      end)

    for {key, value} <- env, do: Application.put_env(:hueworks, key, value)

    on_exit(fn ->
      for {key, original} <- originals do
        case original do
          {:ok, value} -> Application.put_env(:hueworks, key, value)
          :error -> Application.delete_env(:hueworks, key)
        end
      end

      Writer.discard_pending()
    end)

    area = Repo.insert!(%Schemas.Area{name: "Review Area"})

    source =
      Repo.insert!(%Schemas.Bridge{
        name: "Review Hue",
        type: :hue,
        host: "192.0.2.1",
        enabled: true,
        credentials: %{api_key: "test-only"}
      })

    light = insert_light!(area, source, "1")
    %{area: area, source: source, light: light}
  end

  test "an encrypted body read completes when all frame bytes have arrived" do
    key = <<2::256>>
    payload = "hello homekit"
    Process.delete(:send_counter)
    Process.delete(:recv_counter)
    Process.delete(:hap_recv_buffer)
    Process.put(:hap_recv_key, key)
    frame = HAPSessionTransport.encrypted_frames(payload, key)

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(listener)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener)

    try do
      :ok = :gen_tcp.send(client, frame)
      assert HAPSessionTransport.recv(server, byte_size(payload), 500) == {:ok, payload}
    after
      Enum.each([client, server, listener], &:gen_tcp.close/1)

      Enum.each(
        [:hap_recv_key, :hap_recv_buffer, :recv_counter, :send_counter],
        &Process.delete/1
      )
    end
  end

  test "an encrypted body read returns at most the requested bytes and keeps the rest" do
    key = <<2::256>>
    payload = "hello homekit"
    Process.delete(:send_counter)
    Process.delete(:recv_counter)
    Process.delete(:hap_recv_buffer)
    Process.delete(:hap_plaintext_buffer)
    Process.put(:hap_recv_key, key)
    frame = HAPSessionTransport.encrypted_frames(payload, key)

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(listener)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener)

    try do
      :ok = :gen_tcp.send(client, frame)
      assert HAPSessionTransport.recv(server, 5, 500) == {:ok, "hello"}
      assert HAPSessionTransport.recv(server, 0, 500) == {:ok, " homekit"}
      assert HAPSessionTransport.recv(server, 1, 100) == {:error, :timeout}
    after
      Enum.each([client, server, listener], &:gen_tcp.close/1)

      Enum.each(
        [:hap_recv_key, :hap_recv_buffer, :hap_plaintext_buffer, :recv_counter, :send_counter],
        &Process.delete/1
      )
    end
  end

  test "cache expiry notifies subscribers of the actual brightness", %{light: light} do
    State.put(:light, light.id, %{power: :on, brightness: 42})
    start_supervised!(Bridge)
    token = {light.id, 9}
    opts = [kind: :light, id: light.id, characteristic: :brightness]
    Hueworks.HomeKit.put_change_token(opts, token)
    :sys.get_state(Bridge)

    :ok = ValueStore.put_value(73, opts)
    :ok = Writer.flush()
    assert ValueStore.get_value(opts) == {:ok, 73}

    # A bridge can settle at a different value, for example through device quantization.
    State.put(:light, light.id, %{brightness: 72})

    # Expiry must correct subscribers even when there are no more hardware reports.
    assert_receive {:homekit_regression_event, ^token, {:ok, 72}}, 1_500
  end

  test "an executor timeout preserves other already accepted HomeKit writes", %{
    area: area,
    source: source,
    light: light
  } do
    executor = start_supervised!({__MODULE__.TimeoutOnceExecutor, sink: self()})
    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, executor)
    Application.put_env(:hueworks, :homekit_write_coalesce_ms, 0)

    other = insert_light!(area, source, "2")
    State.put(:light, light.id, %{power: :off})
    State.put(:light, other.id, %{power: :off})

    writer = Process.whereis(Writer)
    monitor = Process.monitor(writer)
    :ok = ValueStore.put_value(true, kind: :light, id: light.id)
    first_light_id = light.id
    assert_receive {:homekit_regression_enqueue, [^first_light_id]}, 1_000

    # Accept another command while the first waits on the executor's five-second timeout.
    assert :ok = ValueStore.put_value(true, kind: :light, id: other.id)

    refute_receive {:DOWN, ^monitor, :process, ^writer, _reason}, 5_500

    other_light_id = other.id
    assert_receive {:homekit_regression_enqueue, [^other_light_id]}, 1_000
    assert %{power: :on} = DesiredState.get(:light, other.id)
    :ok = Writer.flush()
    Process.demonitor(monitor, [:flush])
  end

  test "cache expiry corrects subscribers even when the hardware never changes", %{light: light} do
    State.put(:light, light.id, %{power: :on, brightness: 42})
    start_supervised!(Bridge)
    token = {light.id, 9}
    opts = [kind: :light, id: light.id, characteristic: :brightness]
    Hueworks.HomeKit.put_change_token(opts, token)
    :sys.get_state(Bridge)

    :ok = ValueStore.put_value(73, opts)
    :ok = Writer.flush()
    assert ValueStore.get_value(opts) == {:ok, 73}

    # A dropped hardware command leaves the observed value unchanged. The controller
    # still needs a correction from its acknowledged 73 back to the original 42.
    assert_receive {:homekit_regression_event, ^token, {:ok, 42}}, 1_500
  end

  test "a delayed scene activation cannot overwrite a newer HomeKit scene for the same Area", %{
    area: area
  } do
    first = Repo.insert!(%Schemas.Scene{name: "First scene", area_id: area.id})
    second = Repo.insert!(%Schemas.Scene{name: "Second scene", area_id: area.id})
    Application.put_env(:hueworks, :homekit_write_coalesce_ms, 0)
    Phoenix.PubSub.subscribe(Hueworks.PubSub, Hueworks.ActiveScenes.topic())

    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        Repo.config()[:telemetry_prefix] ++ [:query],
        &__MODULE__.pause_scene_read/4,
        %{sink: self(), scene_id: first.id}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok = ValueStore.put_value(true, kind: :scene, id: first.id)
    assert_receive {:paused_scene_read, apply_pid}, 1_000

    try do
      :ok = ValueStore.put_value(true, kind: :scene, id: second.id)
      second_id = second.id

      # Give independent workers an opportunity to finish the newer command first.
      # A correctly serialized writer may defer it until we release the older command.
      receive do
        {:active_scene_updated, _, ^second_id} -> :ok
      after
        1_000 -> :ok
      end
    after
      send(apply_pid, :continue_scene_review)
    end

    :ok = Writer.flush()
    assert Hueworks.ActiveScenes.get_for_area(area.id).scene_id == second.id
  end

  test "a crashed apply does not invalidate a newer write of the same value", %{light: light} do
    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, self())
    Application.put_env(:hueworks, :homekit_write_coalesce_ms, 0)
    Application.put_env(:hueworks, :homekit_value_cache_ttl_ms, 60_000)
    State.put(:light, light.id, %{power: :off})
    opts = [kind: :light, id: light.id]

    :ok = ValueStore.put_value(true, opts)
    assert_receive {:"$gen_call", {first_apply, _tag}, {:enqueue, _, _}}, 1_000

    # Retrying the same command creates a newer accepted write, even though its value
    # equals the older one. Only the older task is being failed here.
    :ok = ValueStore.put_value(true, opts)
    :sys.get_state(Writer)
    Process.exit(first_apply, :kill)

    assert_receive {:"$gen_call", second_from, {:enqueue, _, _}}, 1_000

    try do
      assert ValueStore.get_value(opts) == {:ok, true}
    after
      GenServer.reply(second_from, :ok)
      Writer.flush()
    end
  end

  test "a quick apply failure still corrects the acknowledged brightness", %{
    area: area,
    light: light
  } do
    scene = Repo.insert!(%Schemas.Scene{name: "Scene taking ownership", area_id: area.id})
    Application.put_env(:hueworks, :homekit_notify_debounce_ms, 100)
    State.put(:light, light.id, %{power: :on, brightness: 42})
    start_supervised!(Bridge)
    token = {light.id, 9}
    opts = [kind: :light, id: light.id, characteristic: :brightness]
    Hueworks.HomeKit.put_change_token(opts, token)
    :sys.get_state(Bridge)

    # Hold the notification consumer so acceptance and failure both arrive before its
    # debounce fires, without relying on the test machine winning a sub-100ms race.
    :sys.suspend(Bridge)

    try do
      assert :ok = ValueStore.put_value(73, opts)
      assert ValueStore.get_value(opts) == {:ok, 73}
      {:ok, _} = Hueworks.ActiveScenes.set_active(scene)
      :ok = Writer.flush()
      assert ValueStore.get_value(opts) == {:ok, 42}
    after
      :sys.resume(Bridge)
    end

    assert_receive {:homekit_regression_event, ^token, {:ok, 42}}, 1_500
  end

  test "nonoverlapping light writes preserve both power overrides of their shared active scene",
       %{
         area: area,
         source: source,
         light: light
       } do
    other = insert_light!(area, source, "2")

    {:ok, light_state} =
      Hueworks.Scenes.create_light_state("Warm", :manual, %{"brightness" => "42"})

    {:ok, scene} = Hueworks.Scenes.create_scene(%{name: "Shared scene", area_id: area.id})

    {:ok, _} =
      Hueworks.Scenes.replace_scene_components(scene, [
        %{name: "Both lights", light_ids: [light.id, other.id], light_state_id: light_state.id}
      ])

    {:ok, _, _} = Hueworks.Scenes.activate_scene(scene)
    Application.put_env(:hueworks, :homekit_write_coalesce_ms, 0)
    State.put(:light, light.id, %{power: :on})
    State.put(:light, other.id, %{power: :on})

    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        Repo.config()[:telemetry_prefix] ++ [:query],
        &__MODULE__.pause_override_read/4,
        %{sink: self(), area_id: area.id, gate: :atomics.new(1, []), counter: handler_id}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok = ValueStore.put_value(false, kind: :light, id: light.id)
    assert_receive {:paused_override_read, apply_pid}, 1_000

    try do
      :ok = ValueStore.put_value(false, kind: :light, id: other.id)

      # If the writer runs the second light independently, let it save its override
      # before the first resumes with its old snapshot. Serialization is also valid.
      receive do
        {:override_saved, _other_apply} -> :ok
      after
        1_000 -> :ok
      end
    after
      send(apply_pid, :continue_override_review)
    end

    :ok = Writer.flush()
    active_scene = Hueworks.ActiveScenes.get_for_area(area.id)

    assert Hueworks.ActiveScenes.power_overrides(active_scene) == %{
             light.id => :off,
             other.id => :off
           }
  end

  test "coalescing a newer scene choice preserves its order across pending scene timers", %{
    area: area
  } do
    first = Repo.insert!(%Schemas.Scene{name: "First choice", area_id: area.id})
    second = Repo.insert!(%Schemas.Scene{name: "Second choice", area_id: area.id})
    Application.put_env(:hueworks, :homekit_write_coalesce_ms, 0)
    Phoenix.PubSub.subscribe(Hueworks.PubSub, Hueworks.ActiveScenes.topic())

    # Put all three accepted writes in the mailbox before its readiness timers fire.
    # This reproduces a burst queued while the writer is temporarily descheduled.
    :sys.suspend(Writer)

    try do
      :ok = ValueStore.put_value(true, kind: :scene, id: first.id)
      :ok = ValueStore.put_value(true, kind: :scene, id: second.id)
      :ok = ValueStore.put_value(true, kind: :scene, id: first.id)
    after
      :sys.resume(Writer)
    end

    second_id = second.id

    # Let normal readiness timers dispatch first; an immediate flush would mark every
    # entry ready at once and conceal the difference between timer and acceptance order.
    receive do
      {:active_scene_updated, _, ^second_id} -> :ok
    after
      1_000 -> :ok
    end

    :ok = Writer.flush()
    assert Hueworks.ActiveScenes.get_for_area(area.id).scene_id == first.id
  end

  test "coalescing brightness cannot move an older group On past a newer light Off", %{
    area: area,
    source: source,
    light: light
  } do
    group =
      Repo.insert!(%Schemas.Group{
        name: "Overlapping group",
        source: :hue,
        source_id: "10",
        bridge_id: source.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    Repo.insert!(%Schemas.GroupLight{group_id: group.id, light_id: light.id})
    State.put(:light, light.id, %{power: :off, brightness: 42})

    # Brightness alone does not request power on. Merging it with the earlier group On
    # must not replay that stale power instruction after the intervening light Off.
    :ok = ValueStore.put_value(true, kind: :group, id: group.id)
    :ok = ValueStore.put_value(false, kind: :light, id: light.id)
    :ok = ValueStore.put_value(20, kind: :group, id: group.id, characteristic: :brightness)
    :ok = Writer.flush()

    # Desired state deliberately drops light levels while power is off
    # (LightStateSemantics.normalize_power_off/1), so the brightness applied after the
    # Off leaves no trace; what matters is that the older On was not replayed.
    assert %{power: :off} = DesiredState.get(:light, light.id)
  end

  def pause_override_read(_event, _measurements, metadata, config) do
    if self() != config.sink and metadata.source == "active_scenes" do
      cond do
        String.starts_with?(metadata.query, "SELECT") and metadata.params == [config.area_id] ->
          count = Process.get(config.counter, 0) + 1
          Process.put(config.counter, count)

          # The third lookup is merge_power_overrides' read, after the manual-control
          # and recomputation lookups. Freeze its snapshot before the read/modify/write.
          if count == 3 and :atomics.compare_exchange(config.gate, 1, 0, 1) == :ok do
            send(config.sink, {:paused_override_read, self()})

            receive do
              :continue_override_review -> :ok
            after
              5_000 -> :ok
            end
          end

        String.starts_with?(metadata.query, "UPDATE") ->
          send(config.sink, {:override_saved, self()})

        true ->
          :ok
      end
    end
  end

  def pause_scene_read(_event, _measurements, metadata, %{sink: sink, scene_id: scene_id}) do
    if self() != sink and metadata.source == "scenes" and metadata.params == [scene_id] do
      send(sink, {:paused_scene_read, self()})

      receive do
        :continue_scene_review -> :ok
      after
        5_000 -> :ok
      end
    end
  end

  defp insert_light!(area, source, source_id) do
    Repo.insert!(%Schemas.Light{
      name: "Review Light #{source_id}",
      source: :hue,
      source_id: source_id,
      bridge_id: source.id,
      area_id: area.id,
      homekit_export_mode: :light
    })
  end

  defmodule HAPStub do
    def start_link(_server), do: Supervisor.start_link([], strategy: :one_for_one)
  end

  defmodule PairedStub do
    def paired?(_path), do: true
  end

  defmodule NotifierStub do
    def value_changed({id, 9} = token) do
      value = ValueStore.get_value(kind: :light, id: id, characteristic: :brightness)

      send(
        Application.fetch_env!(:hueworks, :homekit_regression_sink),
        {:homekit_regression_event, token, value}
      )

      :ok
    end
  end

  defmodule TimeoutOnceExecutor do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl true
    def init(opts), do: {:ok, %{sink: Keyword.fetch!(opts, :sink), timed_out?: false}}

    @impl true
    def handle_call({:enqueue, actions, _mode}, _from, state) do
      light_ids = Enum.flat_map(actions, & &1.light_ids) |> Enum.uniq()
      send(state.sink, {:homekit_regression_enqueue, light_ids})

      if state.timed_out? do
        {:reply, :ok, state}
      else
        {:noreply, %{state | timed_out?: true}}
      end
    end
  end
end
