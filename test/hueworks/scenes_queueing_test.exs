defmodule Hueworks.ScenesQueueingTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Control.Executor
  alias Hueworks.Repo
  alias Hueworks.Scenes

  alias Hueworks.Schemas.{
    Group,
    GroupLight,
    Light,
    LightState,
    Room,
    Scene,
    SceneComponent,
    SceneComponentLight
  }

  setup do
    actions_id = {:executor_scene_queueing_actions, self()}
    {:ok, actions_agent} = start_supervised({Agent, fn -> [] end}, id: actions_id)

    dispatch_fun = fn action ->
      Agent.update(actions_agent, fn actions -> actions ++ [action] end)
      :ok
    end

    server = {:global, {:executor_scene_queueing, self()}}

    {:ok, _pid} =
      start_supervised(
        {Executor, name: server, dispatch_fun: dispatch_fun, bridge_rate_fun: fn _ -> 10 end}
      )

    original_enabled = Application.get_env(:hueworks, :control_executor_enabled)
    original_server = Application.get_env(:hueworks, :control_executor_server)

    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, server)

    on_exit(fn ->
      Application.put_env(:hueworks, :control_executor_enabled, original_enabled)
      Application.put_env(:hueworks, :control_executor_server, original_server)
    end)

    {:ok, actions_agent: actions_agent, executor_server: server}
  end

  test "rapid same-bridge room activations dispatch both rooms", %{
    actions_agent: actions_agent,
    executor_server: executor_server
  } do
    bridge =
      insert_bridge!(%{
        name: "Hue Bridge",
        type: :hue,
        host: "192.168.1.15",
        credentials: %{"api_key" => "test"}
      })

    room_one = Repo.insert!(%Room{name: "Bedroom"})
    room_two = Repo.insert!(%Room{name: "Hall"})

    light_one_a =
      Repo.insert!(%Light{
        name: "Bedroom Lamp A",
        display_name: "Bedroom Lamp A",
        source: :hue,
        source_id: "801",
        bridge_id: bridge.id,
        room_id: room_one.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_one_b =
      Repo.insert!(%Light{
        name: "Bedroom Lamp B",
        display_name: "Bedroom Lamp B",
        source: :hue,
        source_id: "803",
        bridge_id: bridge.id,
        room_id: room_one.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    light_two =
      Repo.insert!(%Light{
        name: "Hall Lamp",
        display_name: "Hall Lamp",
        source: :hue,
        source_id: "802",
        bridge_id: bridge.id,
        room_id: room_two.id,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    group_one =
      Repo.insert!(%Group{
        name: "Bedroom Group A",
        display_name: "Bedroom Group A",
        source: :hue,
        source_id: "901",
        bridge_id: bridge.id,
        room_id: room_one.id
      })

    group_one_b =
      Repo.insert!(%Group{
        name: "Bedroom Group B",
        display_name: "Bedroom Group B",
        source: :hue,
        source_id: "903",
        bridge_id: bridge.id,
        room_id: room_one.id
      })

    group_two =
      Repo.insert!(%Group{
        name: "Hall Group",
        display_name: "Hall Group",
        source: :hue,
        source_id: "902",
        bridge_id: bridge.id,
        room_id: room_two.id
      })

    Repo.insert!(%GroupLight{group_id: group_one.id, light_id: light_one_a.id})
    Repo.insert!(%GroupLight{group_id: group_one_b.id, light_id: light_one_b.id})
    Repo.insert!(%GroupLight{group_id: group_two.id, light_id: light_two.id})

    bedroom_state_a =
      insert_light_state!(%{
        name: "Bedroom Warm A",
        type: :manual,
        config: %{"brightness" => "20", "temperature" => "2500"}
      })

    bedroom_state_b =
      insert_light_state!(%{
        name: "Bedroom Warm B",
        type: :manual,
        config: %{"brightness" => "35", "temperature" => "3000"}
      })

    hall_state =
      insert_light_state!(%{
        name: "Hall Warm",
        type: :manual,
        config: %{"brightness" => "30", "temperature" => "2700"}
      })

    bedroom_scene =
      Repo.insert!(%Scene{
        name: "Bedroom Bedtime",
        room_id: room_one.id,
        metadata: %{}
      })

    hall_scene =
      Repo.insert!(%Scene{
        name: "Hall Bedtime",
        room_id: room_two.id,
        metadata: %{}
      })

    bedroom_component_a =
      Repo.insert!(%SceneComponent{
        name: "Bedroom Component A",
        scene_id: bedroom_scene.id,
        light_state_id: bedroom_state_a.id,
        metadata: %{}
      })

    bedroom_component_b =
      Repo.insert!(%SceneComponent{
        name: "Bedroom Component B",
        scene_id: bedroom_scene.id,
        light_state_id: bedroom_state_b.id,
        metadata: %{}
      })

    hall_component =
      Repo.insert!(%SceneComponent{
        name: "Hall Component",
        scene_id: hall_scene.id,
        light_state_id: hall_state.id,
        metadata: %{}
      })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: bedroom_component_a.id,
      light_id: light_one_a.id
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: bedroom_component_b.id,
      light_id: light_one_b.id
    })

    Repo.insert!(%SceneComponentLight{
      scene_component_id: hall_component.id,
      light_id: light_two.id
    })

    reset_states_for_lights([light_one_a.id, light_one_b.id, light_two.id])

    assert {:ok, _diff, _updated} = Scenes.activate_scene(bedroom_scene.id)
    assert {:ok, _diff, _updated} = Scenes.activate_scene(hall_scene.id)

    drain_executor(executor_server)

    actions = Agent.get(actions_agent, & &1)

    assert Enum.map(actions, & &1.id) |> Enum.sort() ==
             Enum.sort([group_one.id, group_one_b.id, group_two.id])
  end

  defp drain_executor(server, attempts \\ 5)

  defp drain_executor(_server, 0), do: :ok

  defp drain_executor(server, attempts) do
    server
    |> Executor.stats()
    |> Map.get(:queues)
    |> Map.values()
    |> Enum.all?(&(&1 == 0))
    |> case do
      true ->
        :ok

      false ->
        Executor.tick(server, force: true)
        drain_executor(server, attempts - 1)
    end
  end

  defp reset_states_for_lights(light_ids) do
    if :ets.whereis(:hueworks_control_state) != :undefined do
      Enum.each(light_ids, fn id ->
        :ets.insert(:hueworks_control_state, {{:light, id}, %{power: :off}})
      end)
    end

    if :ets.whereis(:hueworks_desired_state) != :undefined do
      Enum.each(light_ids, fn id ->
        :ets.delete(:hueworks_desired_state, {:light, id})
      end)
    end
  end

  defp insert_light_state!(attrs) do
    %LightState{}
    |> LightState.changeset(attrs)
    |> Repo.insert!()
  end
end
