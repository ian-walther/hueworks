defmodule HAP.IdentityTest do
  use ExUnit.Case, async: false

  # Explicit accessory and instance IDs (HueWorks fork). Positional defaults must stay
  # byte-for-byte what upstream 0.6.0 publishes.

  setup do
    {:ok, _pid} = start_supervised(HAP.Test.TestValueStore)
    HAP.Test.TestValueStore.put_value(true, value_name: :lightbulb)
    :ok
  end

  defp compile(accessories) do
    HAP.AccessoryServer.compile(%HAP.AccessoryServer{
      identifier: "11:22:33:44:55:66",
      accessories: accessories
    })
  end

  defp lightbulb(overrides \\ []) do
    struct(
      %HAP.Accessory{
        services: [%HAP.Services.LightBulb{on: {HAP.Test.TestValueStore, value_name: :lightbulb}}]
      },
      overrides
    )
  end

  defp explicit_lightbulb(aid, service_iid, on_iid) do
    %HAP.Accessory{
      aid: aid,
      services: [
        %HAP.Service{
          type: "43",
          iid: service_iid,
          characteristics: [{HAP.Characteristics.On, {HAP.Test.TestValueStore, value_name: :lightbulb}, on_iid}]
        }
      ]
    }
  end

  defp ids(server) do
    server
    |> HAP.AccessoryServer.accessories_tree(false)
    |> Map.fetch!(:accessories)
    |> Enum.map(fn accessory ->
      {accessory.aid, Enum.map(accessory.services, &{&1.iid, Enum.map(&1.characteristics, fn c -> c.iid end)})}
    end)
  end

  test "positional defaults are unchanged from upstream" do
    assert ids(compile([lightbulb(), lightbulb()])) == [
             {1, [{1, [3, 5, 7, 9, 11, 13]}, {513, [515]}, {1025, [1027]}]},
             {2, [{1, [3, 5, 7, 9, 11, 13]}, {513, [515]}, {1025, [1027]}]}
           ]
  end

  test "explicit accessory and instance ids are published as given, gaps included" do
    server = compile([lightbulb(aid: 4), explicit_lightbulb(9, 2001, 2005)])

    assert ids(server) == [
             {4, [{1, [3, 5, 7, 9, 11, 13]}, {513, [515]}, {1025, [1027]}]},
             {9, [{1, [3, 5, 7, 9, 11, 13]}, {513, [515]}, {2001, [2005]}]}
           ]
  end

  test "reads and writes route by id, and unknown ids fail rather than reach a neighbour" do
    server = compile([lightbulb(aid: 4), explicit_lightbulb(9, 2001, 2005)])

    assert [%{aid: 9, iid: 2005, value: true, status: 0}] =
             HAP.AccessoryServer.get_characteristics(server, [%{aid: 9, iid: 2005}], :pr, [])

    assert [%{aid: 9, iid: 2003, status: -70_409}] =
             HAP.AccessoryServer.get_characteristics(server, [%{aid: 9, iid: 2003}], :pr, [])

    assert [%{aid: 1, iid: 1027, status: -70_409}] =
             HAP.AccessoryServer.get_characteristics(server, [%{aid: 1, iid: 1027}], :pr, [])

    assert [%{aid: 9, iid: 2005, status: 0}] =
             HAP.AccessoryServer.put_characteristics(server, [%{"aid" => 9, "iid" => 2005, "value" => false}], self())

    assert HAP.Test.TestValueStore.get_value(value_name: :lightbulb) == {:ok, false}

    assert [%{aid: 9, iid: 1027, status: -70_409}] =
             HAP.AccessoryServer.put_characteristics(server, [%{"aid" => 9, "iid" => 1027, "value" => true}], self())
  end

  test "duplicate accessory ids are rejected" do
    assert_raise ArgumentError, ~r/duplicate accessory ids \[4\]/, fn ->
      compile([lightbulb(aid: 4), lightbulb(aid: 4)])
    end
  end

  test "duplicate instance ids within an accessory are rejected" do
    assert_raise ArgumentError, ~r/duplicate instance ids \[513\]/, fn ->
      compile([explicit_lightbulb(1, 513, 2005)])
    end
  end
end
