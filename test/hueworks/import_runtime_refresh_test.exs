defmodule Hueworks.ImportRuntimeRefreshTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Bootstrap.Hue
  alias Hueworks.Control.{DesiredState, ImportRefresh, Planner, State}
  alias Hueworks.{DomainEvents, Import}
  alias Hueworks.Schemas.{Area, Bridge, BridgeImport, Group, Light}
  alias Hueworks.Subscription.{GenericEventStream, HueEventStream}

  setup do
    Phoenix.PubSub.subscribe(Hueworks.PubSub, DomainEvents.topic())

    bridge =
      insert_bridge!(%{
        type: :hue,
        name: "Import refresh",
        host: "unused.invalid",
        credentials: %{api_key: "test-key"}
      })

    %{bridge: bridge}
  end

  test "initial import notifies runtime only after the complete review is applied", %{
    bridge: bridge
  } do
    review = review!(bridge)
    bridge_id = bridge.id

    assert {:ok, %{bridge_import: applied}} =
             Import.apply_review(bridge, review, normalized(), plan())

    assert_receive {:bridge_import_applied, ^bridge_id}
    assert Repo.get!(BridgeImport, applied.id).status == :applied
    assert Repo.get!(Bridge, bridge_id).import_complete
    assert Repo.get_by!(Light, bridge_id: bridge_id, source_id: "1")
    refute_receive {:bridge_import_applied, ^bridge_id}, 20
  end

  test "manual reimport uses the same post-commit boundary", %{bridge: bridge} do
    bridge = bridge |> Ecto.Changeset.change(import_complete: true) |> Repo.update!()
    bridge_id = bridge.id

    assert {:ok, _} = Import.apply_review(bridge, review!(bridge), normalized(), plan())
    assert_receive {:bridge_import_applied, ^bridge_id}
    assert Repo.get_by!(Light, bridge_id: bridge_id, source_id: "1")
    refute_receive {:bridge_import_applied, ^bridge_id}, 20
  end

  test "a failed review does not publish runtime work", %{bridge: bridge} do
    review = review!(bridge)
    Repo.delete!(review)

    assert {:error, _} = Import.apply_review(bridge, review, normalized(), plan())
    refute_receive {:bridge_import_applied, _}, 30
    assert Repo.aggregate(Light, :count) == 0
    refute Repo.get!(Bridge, bridge.id).import_complete
  end

  test "initial import hydrates through a running Hue connection and publishes normal state", %{
    bridge: bridge
  } do
    owner = self()
    connection = start_hue_stream(bridge)

    start_refresh(fn id ->
      assert Repo.get!(Bridge, id).import_complete
      assert Repo.get_by!(BridgeImport, bridge_id: id).status == :applied
      :ok = GenericEventStream.refresh(:import_hue_stream, id)
      Hue.run(Repo.get!(Bridge, id), http_get: http_get(owner))
    end)

    Phoenix.PubSub.subscribe(Hueworks.PubSub, "control_state")
    Phoenix.PubSub.subscribe(Hueworks.PubSub, "bridge_runtime_refresh")

    assert {:ok, _} = Import.apply_review(bridge, review!(bridge), normalized(), plan())
    light = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "1")
    id = light.id
    assert_receive {:control_state, :light, ^id, %{power: :on, brightness: 100}}, 1_000
    assert_receive {:bridge_runtime_refresh, _, %{state: :ready}}, 1_000
    assert_receive {:read, "http://unused.invalid/api/test-key/lights"}
    assert_receive {:read, "http://unused.invalid/api/test-key/groups"}
    assert %{lights_by_id: %{"1" => %{id: ^id}}} = :sys.get_state(connection)
    assert DesiredState.get(:light, id) == nil

    assert {:ok, %{physical_state: %{"power" => "on", "brightness" => 100}}} =
             Hueworks.Api.light(id)

    refute_receive {:sse_connected, _}, 20
  end

  test "reimport refreshes known group membership and stale members without altering intent", %{
    bridge: bridge
  } do
    area = Repo.insert!(%Area{name: "Office"})
    bridge = bridge |> Ecto.Changeset.change(import_complete: true) |> Repo.update!()

    old =
      Repo.insert!(%Light{
        name: "Old",
        bridge_id: bridge.id,
        source: :hue,
        source_id: "1",
        area_id: area.id
      })

    group =
      Repo.insert!(%Group{
        name: "All",
        bridge_id: bridge.id,
        source: :hue,
        source_id: "5",
        area_id: area.id
      })

    connection = start_hue_stream(bridge)
    owner = self()

    start_refresh(fn id ->
      :ok = GenericEventStream.refresh(:import_hue_stream, id)
      send(owner, {:indexes_ready, self()})
      receive do: (:hydrate -> :ok)
      Hue.run(Repo.get!(Bridge, id), http_get: http_get(owner, ["1", "2"]))
    end)

    Phoenix.PubSub.subscribe(Hueworks.PubSub, "bridge_runtime_refresh")

    incoming = %{
      areas: [],
      lights:
        Enum.map(
          ["1", "2"],
          &%{source: :hue, source_id: &1, name: "Light #{&1}", metadata: %{}, capabilities: %{}}
        ),
      groups: [%{source: :hue, source_id: "5", name: "All", metadata: %{}, capabilities: %{}}],
      memberships: %{
        group_lights: Enum.map(["1", "2"], &%{group_source_id: "5", light_source_id: &1})
      }
    }

    selection = %{
      "areas" => %{},
      "lights" => %{"1" => true, "2" => %{"selected" => true, "target_area_id" => "#{area.id}"}},
      "groups" => %{"5" => true}
    }

    assert {:ok, _} = Import.apply_review(bridge, review!(bridge), incoming, selection)
    assert_receive {:indexes_ready, task}, 1_000
    added = Repo.get_by!(Light, bridge_id: bridge.id, source_id: "2")
    desired = %{power: :on, brightness: 100}

    for light <- [old, added] do
      State.put(:light, light.id, %{power: :on, brightness: 10})
      DesiredState.put(:light, light.id, desired)
    end

    before = DesiredState.snapshot([{:light, old.id}, {:light, added.id}])

    stream_state = :sys.get_state(connection)
    assert Enum.sort(stream_state.group_lights[group.id]) == Enum.sort([old.id, added.id])
    assert Map.has_key?(stream_state.lights_by_id, "2")
    assert stream_state.group_light_ids[added.id] == [group.id]

    grouped_event = %{
      "type" => "grouped_light",
      "id_v1" => "/groups/5",
      "on" => %{"on" => true},
      "dimming" => %{"brightness" => 100}
    }

    send_event(connection, grouped_event)
    assert State.get(:light, added.id).brightness == 10

    send(task, :hydrate)
    assert_receive {:bridge_runtime_refresh, _, %{state: :ready}}, 1_000
    assert DesiredState.snapshot([{:light, old.id}, {:light, added.id}]) == before
    assert State.get(:light, old.id).brightness == 100
    assert State.get(:light, added.id).brightness == 100
    assert State.get(:light, added.id).kelvin == 4000

    txn =
      DesiredState.begin(nil)
      |> DesiredState.apply(:light, old.id, desired)
      |> DesiredState.apply(:light, added.id, desired)

    assert {:ok, %{reconcile_diff: diff}} = DesiredState.commit(txn)
    assert diff == %{}
    assert Planner.plan_area(area.id, diff) == []

    send_event(connection, %{
      "type" => "light",
      "id_v1" => "/lights/2",
      "dimming" => %{"brightness" => 45}
    })

    assert State.get(:light, added.id).brightness == 45
    assert State.get(:group, group.id).brightness < 100
  end

  test "runtime failure is retryable without making a committed import fail", %{bridge: bridge} do
    owner = self()

    runtime =
      start_refresh(
        fn id ->
          send(owner, {:refresh_attempt, id, self()})
          receive do: ({:result, result} -> result)
        end,
        retry_ms: 10
      )

    Phoenix.PubSub.subscribe(Hueworks.PubSub, "bridge_runtime_refresh")

    assert {:ok, %{bridge_import: applied}} =
             Import.apply_review(bridge, review!(bridge), normalized(), plan())

    assert_receive {:refresh_attempt, id, task}, 1_000
    send(task, {:result, {:error, :observations}})

    assert_receive {:bridge_runtime_refresh, ^id, %{state: :retrying, error: :observations}},
                   1_000

    assert Repo.get!(BridgeImport, applied.id).status == :applied
    assert_receive {:refresh_attempt, ^id, retry}, 1_000
    send(retry, {:result, :ok})
    assert_receive {:bridge_runtime_refresh, ^id, %{state: :ready, attempt: 2}}, 1_000
    assert %{state: :ready} = ImportRefresh.status(id, runtime)
  end

  test "identity refresh replaces an existing source ID without requiring an unknown event", %{
    bridge: bridge
  } do
    bridge = bridge |> Ecto.Changeset.change(import_complete: true) |> Repo.update!()

    light =
      Repo.insert!(%Light{
        name: "Lamp",
        bridge_id: bridge.id,
        source: :hue,
        source_id: "old",
        external_id: "stable-bulb",
        metadata: %{"uniqueid" => "stable-bulb"}
      })

    State.put(:light, light.id, %{power: :on, brightness: 10})
    connection = start_hue_stream(bridge)
    owner = self()

    start_refresh(fn id ->
      :ok = GenericEventStream.refresh(:import_hue_stream, id)
      Hue.run(Repo.get!(Bridge, id), http_get: http_get(owner))
    end)

    Phoenix.PubSub.subscribe(Hueworks.PubSub, "bridge_runtime_refresh")

    incoming = %{
      normalized()
      | lights: [
          %{
            source: :hue,
            source_id: "1",
            name: "Lamp",
            metadata: %{"uniqueid" => "stable-bulb"},
            capabilities: %{}
          }
        ]
    }

    assert {:ok, _} = Import.apply_review(bridge, review!(bridge), incoming, plan())
    assert_receive {:bridge_runtime_refresh, _, %{state: :ready}}, 1_000
    assert Repo.get!(Light, light.id).source_id == "1"
    assert Repo.aggregate(Light, :count) == 1
    assert Map.keys(:sys.get_state(connection).lights_by_id) == ["1"]
    assert %{brightness: 100, kelvin: 4000} = State.get(:light, light.id)
  end

  test "review owns the transaction boundary rather than notifying before an outer rollback", %{
    bridge: bridge
  } do
    review = review!(bridge)

    assert {:error, :outer_rollback} =
             Repo.transaction(fn ->
               assert {:error, :nested_import_transaction} =
                        Import.apply_review(bridge, review, normalized(), plan())

               Repo.rollback(:outer_rollback)
             end)

    refute_receive {:bridge_import_applied, _}, 20
    assert Repo.aggregate(Light, :count) == 0
  end

  defp start_hue_stream(bridge) do
    Process.register(self(), :import_hue_listener)

    start_supervised!(
      {HueEventStream, name: :import_hue_stream, connection_module: __MODULE__.HueConnection}
    )

    assert_receive {:sse_connected, connection}, 1_000
    assert :sys.get_state(connection).bridge.id == bridge.id
    connection
  end

  defp start_refresh(fun, opts \\ []) do
    tasks = start_supervised!({Task.Supervisor, []})

    start_supervised!(
      {ImportRefresh,
       [
         name: :import_refresh_test,
         refresh_fun: fun,
         task_supervisor: tasks,
         recover_on_start: false
       ] ++ opts}
    )
  end

  defp http_get(owner, ids \\ ["1"]) do
    fn url, [], _opts ->
      send(owner, {:read, url})

      body =
        if String.ends_with?(url, "/lights") do
          Map.new(ids, &{&1, %{"state" => %{"on" => true, "bri" => 254, "ct" => 250}}})
        else
          %{"5" => %{"action" => %{"on" => true, "bri" => 254}}}
        end

      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
    end
  end

  defp send_event(connection, event) do
    ref = :sys.get_state(connection).ref

    send(connection, %HTTPoison.AsyncChunk{
      id: ref,
      chunk: "data: " <> Jason.encode!(event) <> "\n\n"
    })

    :sys.get_state(connection)
  end

  defmodule HueConnection do
    alias Hueworks.Subscription.HueEventStream.Connection

    def start_link(bridge) do
      Connection.start_link(bridge,
        http_get: fn _url, _headers, _opts ->
          send(Process.whereis(:import_hue_listener), {:sse_connected, self()})
          {:ok, %HTTPoison.AsyncResponse{id: make_ref()}}
        end
      )
    end

    defdelegate refresh(pid, bridge), to: Connection
  end

  defp review!(bridge) do
    Repo.insert!(%BridgeImport{
      bridge_id: bridge.id,
      raw_blob: %{},
      normalized_blob: %{},
      status: :normalized,
      imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp normalized do
    %{
      areas: [],
      lights: [
        %{source: :hue, source_id: "1", name: "New light", metadata: %{}, capabilities: %{}}
      ],
      groups: [],
      memberships: %{}
    }
  end

  defp plan, do: %{"areas" => %{}, "lights" => %{"1" => true}, "groups" => %{}}
end
