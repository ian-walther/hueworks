defmodule Hueworks.HomeKitPairingIdentityReviewTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.HomeKit
  alias Hueworks.HomeKit.{AccessoryGraph, Bridge}
  alias Hueworks.Schemas.{Area, Light}
  alias __MODULE__.PairingStateStub

  setup do
    owner = self()
    state = start_supervised!({Agent, fn -> %{paired?: false, owner: owner} end})

    overrides = [
      homekit_hap_module: __MODULE__.HAPStub,
      homekit_pairing_state_module: __MODULE__.PairingStateStub,
      homekit_pairing_identity_review_state: state,
      homekit_publish_after_pairing_delay_ms: 0
    ]

    originals = Enum.map(overrides, fn {key, _} -> {key, Application.get_env(:hueworks, key)} end)
    Enum.each(overrides, fn {key, value} -> Application.put_env(:hueworks, key, value) end)

    on_exit(fn ->
      Enum.each(originals, fn {key, value} -> restore_app_env(:hueworks, key, value) end)
    end)

    area = Repo.insert!(%Area{name: "Pairing identity review"})

    bridge =
      insert_bridge!(%{
        name: "Pairing identity review bridge",
        type: :hue,
        host: "192.0.2.1",
        credentials: %{api_key: "test-only"}
      })

    for name <- ["First", "Second"] do
      Repo.insert!(%Light{
        name: name,
        display_name: name,
        source: :hue,
        source_id: name,
        bridge_id: bridge.id,
        area_id: area.id,
        supports_color: true,
        supports_temp: true,
        homekit_export_mode: :light
      })
    end

    :ok
  end

  for {installation, initially_paired?, first_entity_aid} <- [
        {"legacy", true, 1},
        {"fresh", false, 2}
      ] do
    test "#{installation} identity table survives pairing reset with a bridge-only shell" do
      PairingStateStub.put(unquote(initially_paired?))
      assert {:ok, initial, _} = AccessoryGraph.build()

      assert Enum.find(initial.accessories, &(&1.name == "First")).aid ==
               unquote(first_entity_aid)

      PairingStateStub.put(true)
      start_supervised!({Bridge, []})
      assert_receive {:hap_started, paired_server}, 1_000
      original_tree = wire_tree(paired_server)

      # Exercise the public Reset Pairing operation with a pre-existing identity table,
      # not just an unpaired first boot that reserves a new bridge slot.
      assert {:ok, 1} = HomeKit.reset_pairings()
      assert_receive {:hap_started, shell}, 1_000
      shell_tree = wire_tree(shell)

      assert Enum.map(shell_tree.accessories, & &1.aid) == [1],
             "Reset Pairing must publish a bridge-only primary; got #{inspect(shell_tree)}"

      [primary] = shell_tree.accessories
      assert Enum.sort(Enum.map(primary.services, & &1.type)) == ["3E", "A2"]

      PairingStateStub.put(true)
      send(Bridge, :pairing_watchdog)
      assert_receive {:hap_started, repaired_server}, 1_000
      assert wire_tree(repaired_server) == original_tree
    end
  end

  defp wire_tree(server) do
    server
    |> HAP.AccessoryServer.compile()
    |> HAP.AccessoryServer.accessories_tree(false)
  end

  defmodule HAPStub do
    def start_link(server) do
      state = Application.fetch_env!(:hueworks, :homekit_pairing_identity_review_state)
      owner = Agent.get(state, & &1.owner)
      send(owner, {:hap_started, server})
      Supervisor.start_link([], strategy: :one_for_one)
    end
  end

  defmodule PairingStateStub do
    def put(paired?) do
      Agent.update(state(), &Map.put(&1, :paired?, paired?))
    end

    def paired?(_data_path), do: Agent.get(state(), & &1.paired?)

    def clear_pairings(_data_path) do
      Agent.get_and_update(state(), fn current ->
        count = if current.paired?, do: 1, else: 0
        {{:ok, count}, %{current | paired?: false}}
      end)
    end

    defp state do
      Application.fetch_env!(:hueworks, :homekit_pairing_identity_review_state)
    end
  end
end
