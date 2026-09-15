defmodule Hueworks.HomeKitColorReviewTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.Color
  alias Hueworks.Control.{DesiredState, State}
  alias Hueworks.HomeKit.{AccessoryGraph, ValueCache, ValueStore, Writer}
  alias Hueworks.Schemas

  setup do
    # Model an install paired before identities were persisted, so entities keep the
    # positional numbering they already published (a fresh install puts the bridge at 1).
    original_pairing_state = Application.get_env(:hueworks, :homekit_pairing_state_module)
    Application.put_env(:hueworks, :homekit_pairing_state_module, __MODULE__.PairedStub)

    on_exit(fn ->
      case original_pairing_state do
        nil -> Application.delete_env(:hueworks, :homekit_pairing_state_module)
        value -> Application.put_env(:hueworks, :homekit_pairing_state_module, value)
      end
    end)

    :ok = Writer.discard_pending()

    env = [
      control_executor_enabled: false,
      homekit_write_coalesce_ms: 60_000,
      homekit_value_cache_ttl_ms: 60_000
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

    area = Repo.insert!(%Schemas.Area{name: "Color review"})

    bridge =
      Repo.insert!(%Schemas.Bridge{
        name: "Color review Hue",
        type: :hue,
        host: "192.0.2.1",
        enabled: true,
        credentials: %{api_key: "test-only"}
      })

    light =
      Repo.insert!(%Schemas.Light{
        name: "Color review light",
        display_name: "Color review light",
        source: :hue,
        source_id: "1",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light,
        supports_color: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    {x, y} = Color.hs_to_xy(0, 100)
    initial = %{power: :on, brightness: 50, x: x, y: y}
    DesiredState.put(:light, light.id, initial)
    State.put(:light, light.id, initial)

    %{area: area, bridge: bridge, light: light, initial: initial}
  end

  test "a confirmed temperature supersedes cached color from an earlier completed write", %{
    light: light
  } do
    :ok = write(light, :hue, 120)
    :ok = write(light, :saturation, 80)
    :ok = Writer.flush()

    # This is a second apply, not a conflict inside the same coalescing window.
    :ok = write(light, :color_temperature, 250)
    :ok = Writer.flush()
    assert %{kelvin: 4000} = DesiredState.get(:light, light.id)

    observed = State.put(:light, light.id, %{kelvin: 4000})
    ValueCache.reconcile(:light, light.id, observed)

    for characteristic <- [:hue, :saturation] do
      assert {:ok, value} =
               ValueStore.get_value(kind: :light, id: light.id, characteristic: characteristic)

      assert_in_delta value, ValueStore.observed_value(characteristic, observed), 2.0
    end
  end

  test "a color write supersedes temperature cached by an earlier completed apply", %{
    light: light
  } do
    :ok = write(light, :color_temperature, 250)
    :ok = Writer.flush()
    assert ValueCache.get(:light, light.id, :color_temperature) == {:ok, 250}

    :ok = write(light, :hue, 120)
    :ok = write(light, :saturation, 80)
    :ok = Writer.flush()

    assert ValueCache.get(:light, light.id, :color_temperature) == :miss
    assert ValueCache.get(:light, light.id, :hue) == {:ok, 120.0}
    assert ValueCache.get(:light, light.id, :saturation) == {:ok, 80.0}
    {x, y} = Color.hs_to_xy(120, 80)
    assert %{x: ^x, y: ^y} = desired = DesiredState.get(:light, light.id)
    refute Map.has_key?(desired, :kelvin)
  end

  test "an older mode change and failed apply cannot clear newer same-valued color", %{
    light: light
  } do
    old_hue = ValueCache.put(:light, light.id, :hue, 120.0)
    old_saturation = ValueCache.put(:light, light.id, :saturation, 80.0)
    temperature = ValueCache.put(:light, light.id, :color_temperature, 250)
    new_hue = ValueCache.put(:light, light.id, :hue, 120.0)

    # The older temperature supersedes the old saturation but not the newer hue.
    ValueCache.invalidate_older(:light, light.id, [:hue, :saturation], temperature)
    assert ValueCache.get(:light, light.id, :hue) == {:ok, 120.0}
    assert ValueCache.get(:light, light.id, :saturation) == :miss

    ValueCache.put(:light, light.id, :saturation, 80.0)
    ValueCache.invalidate(:light, light.id, %{hue: old_hue, saturation: old_saturation})
    ValueCache.invalidate_older(:light, light.id, [:color_temperature], new_hue)

    assert ValueCache.get(:light, light.id, :hue) == {:ok, 120.0}
    assert ValueCache.get(:light, light.id, :saturation) == {:ok, 80.0}
    assert ValueCache.get(:light, light.id, :color_temperature) == :miss
  end

  test "a partial color write uses preceding group intent before hardware reports it", %{
    area: area,
    bridge: bridge,
    light: light,
    initial: initial
  } do
    group =
      Repo.insert!(%Schemas.Group{
        name: "Color review group",
        display_name: "Color review group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light,
        supports_color: true,
        supports_temp: true,
        reported_min_kelvin: 2000,
        reported_max_kelvin: 6500
      })

    Repo.insert!(%Schemas.GroupLight{group_id: group.id, light_id: light.id})
    State.put(:group, group.id, initial)

    :ok =
      ValueStore.put_value(250, kind: :group, id: group.id, characteristic: :color_temperature)

    :ok = write(light, :saturation, 50)
    :ok = Writer.flush()

    # Changing saturation after the group temperature must not resurrect the old red.
    hue = ValueStore.observed_value(:hue, %{kelvin: 4000})
    {expected_x, expected_y} = Color.hs_to_xy(hue, 50)
    assert %{x: x, y: y} = DesiredState.get(:light, light.id)
    assert_in_delta x, expected_x, 0.0001
    assert_in_delta y, expected_y, 0.0001
  end

  test "a partial color write cannot borrow saturation from a later queued command", %{
    area: area,
    bridge: bridge,
    light: light
  } do
    other =
      Repo.insert!(%Schemas.Light{
        name: "Other color review light",
        display_name: "Other color review light",
        source: :hue,
        source_id: "2",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    probe = start_supervised!({__MODULE__.RecordingExecutor, sink: self(), light_id: light.id})
    Application.put_env(:hueworks, :control_executor_enabled, true)
    Application.put_env(:hueworks, :control_executor_server, probe)

    :ok = write(light, :hue, 120)
    :ok = write(other, :on, false)
    :ok = write(light, :saturation, 30)
    :ok = Writer.flush()

    # The intervening write deliberately prevents merging the two color writes.
    assert_receive {:color_review_intent, %{x: x, y: y}}, 1000
    {expected_x, expected_y} = Color.hs_to_xy(120, 100)
    assert_in_delta x, expected_x, 0.0001
    assert_in_delta y, expected_y, 0.0001
  end

  test "temperature writes honor the calibrated actual range, not the bridge wire range", %{
    bridge: bridge,
    light: light
  } do
    bridge |> Ecto.Changeset.change(type: :z2m, credentials: %{}) |> Repo.update!()

    light =
      light
      |> Ecto.Changeset.change(
        source: :z2m,
        reported_min_kelvin: 2700,
        reported_max_kelvin: 6500,
        actual_min_kelvin: 2000,
        actual_max_kelvin: 6500
      )
      |> Repo.update!()

    assert Hueworks.Kelvin.derive_range(light) == {2000, 6500}
    :ok = write(light, :color_temperature, 500)
    :ok = Writer.flush()

    assert %{kelvin: 2000} = DesiredState.get(:light, light.id)
  end

  test "adding color capability preserves a group's existing temperature characteristic ID", %{
    area: area,
    bridge: bridge,
    light: light
  } do
    light
    |> Ecto.Changeset.change(homekit_export_mode: :none)
    |> Repo.update!()

    group =
      Repo.insert!(%Schemas.Group{
        name: "Temperature review group",
        display_name: "Temperature review group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light,
        supports_color: false,
        supports_temp: true
      })

    Repo.insert!(%Schemas.GroupLight{group_id: group.id, light_id: light.id})

    before = temperature_identity()

    # Group capability refresh can add color when a color bulb joins a white-only group.
    group
    |> Ecto.Changeset.change(supports_color: true)
    |> Repo.update!()

    assert temperature_identity() == before
  end

  test "adding temperature capability preserves a group's existing color characteristic IDs", %{
    area: area,
    bridge: bridge,
    light: light
  } do
    light
    |> Ecto.Changeset.change(homekit_export_mode: :none)
    |> Repo.update!()

    group =
      Repo.insert!(%Schemas.Group{
        name: "RGB review group",
        display_name: "RGB review group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light,
        supports_color: true,
        supports_temp: false
      })

    Repo.insert!(%Schemas.GroupLight{group_id: group.id, light_id: light.id})
    before = color_identities()

    # Reimport can add temperature capability when a CT-capable member joins an RGB group.
    group |> Ecto.Changeset.change(supports_temp: true) |> Repo.update!()

    assert color_identities() == before
  end

  for {description, capabilities} <- [
        {"temperature is lost and restored", [{true, true}, {true, false}, {true, true}]},
        {"color is lost after temperature was appended",
         [{true, false}, {true, true}, {false, true}, {true, true}]},
        {"color is added while a former temperature slot is absent",
         [{false, true}, {false, false}, {true, false}, {true, true}]}
      ] do
    @capability_lifecycle capabilities

    test "published characteristic identities survive when #{description}", %{
      area: area,
      bridge: bridge,
      light: light
    } do
      light |> Ecto.Changeset.change(homekit_export_mode: :none) |> Repo.update!()

      group =
        Repo.insert!(%Schemas.Group{
          name: "Lifecycle review group",
          display_name: "Lifecycle review group",
          source: :hue,
          source_id: "10",
          bridge_id: bridge.id,
          area_id: area.id,
          homekit_export_mode: :light
        })

      Repo.insert!(%Schemas.GroupLight{group_id: group.id, light_id: light.id})

      {_group, _original_ids, moves} =
        Enum.reduce(@capability_lifecycle, {group, %{}, []}, fn {color?, temp?},
                                                                {group, original, moves} ->
          group =
            group
            |> Ecto.Changeset.change(supports_color: color?, supports_temp: temp?)
            |> Repo.update!()

          saved = Repo.get!(Schemas.Group, group.id)
          assert {saved.supports_color, saved.supports_temp} == {color?, temp?}

          current = lightbulb_identities()

          moves =
            Enum.reduce(current, moves, fn {type, identity}, acc ->
              case Map.fetch(original, type) do
                {:ok, previous} when previous != identity ->
                  [{type, previous, identity, {color?, temp?}} | acc]

                _ ->
                  acc
              end
            end)

          # Remember the first published ID even through periods when a type is absent.
          {group, Map.merge(current, original), moves}
        end)

      assert Enum.reverse(moves) == []
    end
  end

  test "light, group and scene control identities survive renamed and inserted accessories", %{
    area: area,
    bridge: bridge,
    light: light
  } do
    {:ok, _} =
      Hueworks.AppSettings.upsert_global(%{
        latitude: 40.0,
        longitude: -75.0,
        timezone: "America/New_York",
        homekit_scenes_enabled: true
      })

    group =
      Repo.insert!(%Schemas.Group{
        name: "Review group",
        display_name: "Review group",
        source: :hue,
        source_id: "10",
        bridge_id: bridge.id,
        area_id: area.id,
        homekit_export_mode: :light
      })

    Repo.insert!(%Schemas.GroupLight{group_id: group.id, light_id: light.id})
    scene = Repo.insert!(%Schemas.Scene{name: "Review scene", area_id: area.id})
    before = control_identities()

    for entity <- [light, group, scene] do
      entity
      |> Ecto.Changeset.change(
        name: "Renamed #{entity.name}",
        display_name: "Renamed #{entity.name}"
      )
      |> Repo.update!()
    end

    Repo.insert!(%Schemas.Light{
      name: "Alphabetically first light",
      display_name: "Alphabetically first light",
      source: :hue,
      source_id: "2",
      bridge_id: bridge.id,
      area_id: area.id,
      homekit_export_mode: :light
    })

    assert control_identities() |> Map.take(Map.keys(before)) == before
  end

  defp write(light, characteristic, value) do
    ValueStore.put_value(value, kind: :light, id: light.id, characteristic: characteristic)
  end

  defp temperature_identity do
    {:ok, server, _topology} = AccessoryGraph.build()

    tree =
      server
      |> HAP.AccessoryServer.compile()
      |> HAP.AccessoryServer.accessories_tree(false)

    accessory = hd(tree.accessories)
    service = Enum.find(accessory.services, &(&1.type == "43"))
    characteristic = Enum.find(service.characteristics, &(&1.type == "CE"))
    {accessory.aid, characteristic.iid}
  end

  defp control_identities do
    {:ok, server, _topology} = AccessoryGraph.build()

    tree =
      server
      |> HAP.AccessoryServer.compile()
      |> HAP.AccessoryServer.accessories_tree()

    Map.new(tree.accessories, fn accessory ->
      information = Enum.find(accessory.services, &(&1.type == "3E"))
      serial = Enum.find(information.characteristics, &(&1.type == "30")).value
      control = Enum.find(accessory.services, &(&1.type in ["43", "49"]))
      characteristics = Map.new(control.characteristics, &{&1.type, &1.iid})
      {serial, {accessory.aid, Map.take(characteristics, ["25", "8"])}}
    end)
  end

  defp color_identities do
    {:ok, server, _topology} = AccessoryGraph.build()

    tree =
      server
      |> HAP.AccessoryServer.compile()
      |> HAP.AccessoryServer.accessories_tree(false)

    accessory = hd(tree.accessories)
    service = Enum.find(accessory.services, &(&1.type == "43"))

    service.characteristics
    |> Enum.filter(&(&1.type in ["13", "2F"]))
    |> Map.new(&{&1.type, {accessory.aid, &1.iid}})
  end

  defp lightbulb_identities do
    {:ok, server, _topology} = AccessoryGraph.build()

    tree =
      server
      |> HAP.AccessoryServer.compile()
      |> HAP.AccessoryServer.accessories_tree(false)

    accessory = hd(tree.accessories)
    service = Enum.find(accessory.services, &(&1.type == "43"))
    Map.new(service.characteristics, &{&1.type, {accessory.aid, &1.iid}})
  end

  defmodule RecordingExecutor do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl true
    def init(opts), do: {:ok, Map.new(opts)}

    @impl true
    def handle_call({:enqueue, _actions, _mode}, _from, state) do
      send(state.sink, {:color_review_intent, DesiredState.get(:light, state.light_id)})
      {:reply, :ok, state}
    end
  end

  defmodule PairedStub do
    def paired?(_data_path), do: true
  end
end
