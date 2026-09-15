defmodule Hueworks.HomeKitIdentityReviewTest do
  use Hueworks.DataCase, async: false

  alias Hueworks.HomeKit.{AccessoryGraph, ValueStore}
  alias Hueworks.Schemas.{Area, Light}

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

    area = Repo.insert!(%Area{name: "Identity review"})

    bridge =
      insert_bridge!(%{
        name: "Identity review bridge",
        type: :hue,
        host: "192.0.2.1",
        credentials: %{api_key: "test-only"}
      })

    %{area: area, bridge: bridge}
  end

  test "retiring the first exposed light retains the primary accessory and surviving IDs",
       context do
    first = light!(context, "first")
    second = light!(context, "second")
    {:ok, initial, _topology} = AccessoryGraph.build()

    second_aid =
      Enum.find(initial.accessories, &(&1.serial_number == "light-#{second.id}")).aid

    first |> change(homekit_export_mode: :none) |> Repo.update!()
    {:ok, updated, _topology} = AccessoryGraph.build()
    tree = updated |> HAP.AccessoryServer.compile() |> HAP.AccessoryServer.accessories_tree(false)

    assert Enum.find(updated.accessories, &(&1.serial_number == "light-#{second.id}")).aid ==
             second_aid

    # AID 1 is the primary HAP accessory, not an optional bridged-light slot.
    assert Enum.any?(tree.accessories, &(&1.aid == 1)),
           "retiring a light removed the primary accessory; published AIDs: #{inspect(Enum.map(tree.accessories, & &1.aid))}"
  end

  test "color-capable production shapes retain their old On, Brightness, and Name addresses",
       context do
    lights = [light!(context, "dimmer"), light!(context, "switch", :switch)]

    # Production's graph uses the upstream service and does not expose color even when
    # the light supports it. Do not derive this baseline from the new color service.
    legacy = %HAP.AccessoryServer{
      identifier: "11:22:33:44:55:66",
      accessories:
        Enum.map(lights, fn light ->
          opts = [kind: :light, id: light.id]

          %HAP.Accessory{
            serial_number: "light-#{light.id}",
            name: light.display_name,
            services: [
              %HAP.Services.LightBulb{
                on: {ValueStore, Keyword.put(opts, :characteristic, :on)},
                brightness:
                  if(light.homekit_export_mode == :light,
                    do: {ValueStore, Keyword.put(opts, :characteristic, :brightness)}
                  ),
                name: light.display_name
              }
            ]
          }
        end)
    }

    old = addresses(legacy)
    {:ok, upgraded, _topology} = AccessoryGraph.build()
    new = addresses(upgraded)

    for {address, type} <- old, do: assert(Map.fetch!(new, address) == type)
    assert map_size(new) > map_size(old)
  end

  test "export-mode and color-capability changes preserve every previously published address",
       context do
    light = light!(context, "changing", :switch)

    states = [
      {:switch, true, true},
      {:light, true, true},
      {:switch, false, false},
      {:light, false, true},
      {:light, true, false},
      {:light, false, false},
      {:light, true, true},
      {:switch, true, true}
    ]

    Enum.reduce(states, {light, %{}}, fn {mode, color?, temp?}, {light, seen} ->
      light =
        light
        |> change(homekit_export_mode: mode, supports_color: color?, supports_temp: temp?)
        |> Repo.update!()

      {:ok, server, _topology} = AccessoryGraph.build()
      current = addresses(server) |> Map.new(fn {address, type} -> {type, address} end)

      for {type, address} <- current, Map.has_key?(seen, type) do
        assert seen[type] == address
      end

      {light, Map.merge(seen, current)}
    end)
  end

  defp light!(%{area: area, bridge: bridge}, name, mode \\ :light) do
    Repo.insert!(%Light{
      name: name,
      display_name: name,
      source: :hue,
      source_id: name,
      bridge_id: bridge.id,
      area_id: area.id,
      supports_color: true,
      supports_temp: true,
      homekit_export_mode: mode
    })
  end

  defp addresses(server) do
    server
    |> HAP.AccessoryServer.compile()
    |> HAP.AccessoryServer.accessories_tree(false)
    |> Map.fetch!(:accessories)
    |> Enum.flat_map(fn accessory ->
      accessory.services
      |> Enum.filter(&(&1.type == "43"))
      |> Enum.flat_map(fn service ->
        [{{accessory.aid, service.iid}, {:service, service.type}}] ++
          Enum.map(service.characteristics, &{{accessory.aid, &1.iid}, &1.type})
      end)
    end)
    |> Map.new()
  end

  defmodule PairedStub do
    def paired?(_data_path), do: true
  end
end
