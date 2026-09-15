defmodule HAP.IdentityReviewTest do
  use ExUnit.Case, async: false

  defmodule Source do
    @behaviour HAP.ValueStore

    @impl true
    def get_value(opts), do: {:ok, Keyword.fetch!(opts, :value)}

    @impl true
    def put_value(value, opts) do
      send(Keyword.fetch!(opts, :owner), {:write, Keyword.fetch!(opts, :key), value})
      :ok
    end

    @impl true
    def set_change_token(token, opts) do
      send(Keyword.fetch!(opts, :owner), {:subscription, Keyword.fetch!(opts, :key), token})
      :ok
    end
  end

  setup tags do
    unless tags[:http], do: start_supervised!(HAP.EventManager)
    :ok
  end

  @tag :http
  test "encrypted HTTP reads, writes, and notifications use the explicit addresses" do
    accessories = [
      %HAP.Accessory{aid: 1, name: "Test bridge"},
      accessory(9, [
        service(70000, [
          {HAP.Characteristics.On, true, 70002},
          characteristic(:remote, 70004, 29)
        ])
      ])
    ]

    [accessories: accessories]
    |> HAP.Test.TestAccessoryServer.test_server()
    |> start_supervised!()

    {:ok, client} = HAP.Test.HTTPClient.init(:localhost, HAP.AccessoryServerManager.port())

    try do
      :ok = HAP.Test.HTTPClient.setup_encrypted_session(client)

      assert {:ok, 200, _headers, body} =
               HAP.Test.HTTPClient.get(client, "/characteristics?id=9.70004")

      assert Jason.decode!(body) == %{
               "characteristics" => [%{"aid" => 9, "iid" => 70004, "value" => 29}]
             }

      headers = ["content-type": "application/hap+json"]

      request = Jason.encode!(%{characteristics: [%{aid: 9, iid: 70004, value: 63}]})
      assert {:ok, 204, _, _} = HAP.Test.HTTPClient.put(client, "/characteristics", request, headers)
      assert_receive {:write, :remote, 63}

      request = Jason.encode!(%{characteristics: [%{aid: 9, iid: 70004, ev: true}]})
      assert {:ok, 204, _, _} = HAP.Test.HTTPClient.put(client, "/characteristics", request, headers)
      assert_receive {:subscription, :remote, {9, 70004}}

      HAP.AccessoryServerManager.value_changed({9, 70004})

      assert {:ok, "EVENT/1.0 200 OK\r\n" <> event} =
               HAP.HAPSessionTransport.recv(client, 0, 1000)

      [_headers, body] = String.split(event, "\r\n\r\n", parts: 2)

      assert Jason.decode!(body) == %{
               "characteristics" => [%{"aid" => 9, "iid" => 70004, "value" => 29, "status" => 0}]
             }

      request = Jason.encode!(%{characteristics: [%{aid: 9, iid: 1027, value: 99}]})
      assert {:ok, 207, _, body} = HAP.Test.HTTPClient.put(client, "/characteristics", request, headers)

      assert Jason.decode!(body) == %{
               "characteristics" => [%{"aid" => 9, "iid" => 1027, "status" => -70_409}]
             }

      refute_receive {:write, _, 99}, 0
    after
      :gen_tcp.close(client)
    end
  end

  test "duplicate characteristic types in reordered services retain distinct routing and event IDs" do
    a = accessory(4, [service(2000, [characteristic(:a, 2002, 17)])])

    b =
      accessory(9, [
        service(3000, [characteristic(:b, 3002, 29)]),
        service(70000, [characteristic(:c, 70002, 41)])
      ])

    shapes = [
      [a, b],
      [%{b | services: Enum.reverse(b.services)}, a],
      [%{b | services: [List.last(b.services)]}],
      [b, a]
    ]

    for shape <- shapes do
      server = compile(shape)

      assert [%{aid: 9, iid: 70002, value: 41, status: 0}] =
               HAP.AccessoryServer.get_characteristics(server, [%{aid: 9, iid: 70002}], :pr, [])

      assert [%{status: 0}] =
               HAP.AccessoryServer.put_characteristics(
                 server,
                 [%{"aid" => 9, "iid" => 70002, "value" => 63}],
                 self()
               )

      assert_receive {:write, :c, 63}
      refute_receive {:write, :a, _}, 0
      refute_receive {:write, :b, _}, 0

      assert [%{status: 0}] =
               HAP.AccessoryServer.put_characteristics(
                 server,
                 [%{"aid" => 9, "iid" => 70002, "ev" => true}],
                 self()
               )

      assert_receive {:subscription, :c, {9, 70002}}
      HAP.AccessoryServer.value_changed(server, %{aid: 9, iid: 70002})

      assert_receive {:"$gen_cast", {:push, %{characteristics: [%{aid: 9, iid: 70002, value: 41, status: 0}]}}}

      assert [%{status: 0}] =
               HAP.AccessoryServer.put_characteristics(
                 server,
                 [%{"aid" => 9, "iid" => 70002, "ev" => false}],
                 self()
               )

      HAP.AccessoryServer.value_changed(server, %{aid: 9, iid: 70002})
      refute_receive {:"$gen_cast", {:push, _}}, 0
    end
  end

  test "removed IDs reject writes and subscriptions without notifying or changing a neighbour" do
    server = compile([accessory(9, [service(2000, [characteristic(:survivor, 2006, 31)])])])

    for {aid, iid} <- [{4, 2006}, {9, 2002}, {9, 2000}, {9, 1027}] do
      assert [%{status: -70_409}] =
               HAP.AccessoryServer.get_characteristics(server, [%{aid: aid, iid: iid}], :pr, [])

      for action <- [%{"value" => 99}, %{"ev" => true}] do
        assert [%{status: -70_409}] =
                 HAP.AccessoryServer.put_characteristics(
                   server,
                   [Map.merge(%{"aid" => aid, "iid" => iid}, action)],
                   self()
                 )
      end

      assert HAP.EventManager.get_listeners(aid, iid) == []
    end

    refute_receive {:write, _, _}, 0
    refute_receive {:subscription, _, _}, 0
  end

  test "a nil source with an explicit IID is absent without shifting surviving characteristics" do
    server =
      compile([
        accessory(9, [
          service(2000, [
            {HAP.Characteristics.Brightness, nil, 2002},
            characteristic(:survivor, 2004, 37)
          ])
        ])
      ])

    assert [%{status: -70_409}] =
             HAP.AccessoryServer.get_characteristics(server, [%{aid: 9, iid: 2002}], :pr, [])

    assert [%{value: 37, status: 0}] =
             HAP.AccessoryServer.get_characteristics(server, [%{aid: 9, iid: 2004}], :pr, [])
  end

  test "duplicate IDs are rejected across service and characteristic boundaries" do
    for conflicting <- [
          service(2002, [characteristic(:b, 4000, 2)]),
          service(3000, [characteristic(:b, 2002, 2)]),
          service(3000, [characteristic(:b, 2000, 2)])
        ] do
      assert_raise ArgumentError, ~r/duplicate instance ids/, fn ->
        compile([accessory(9, [service(2000, [characteristic(:a, 2002, 1)]), conflicting])])
      end
    end
  end

  defp accessory(aid, services), do: %HAP.Accessory{aid: aid, services: services}

  defp service(iid, characteristics),
    do: %HAP.Service{type: "43", iid: iid, characteristics: characteristics}

  defp characteristic(key, iid, value),
    do: {HAP.Characteristics.Brightness, {Source, owner: self(), key: key, value: value}, iid}

  defp compile(accessories),
    do:
      HAP.AccessoryServer.compile(%HAP.AccessoryServer{
        identifier: "11:22:33:44:55:66",
        accessories: accessories
      })
end
