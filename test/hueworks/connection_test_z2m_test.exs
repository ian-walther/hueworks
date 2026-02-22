defmodule Hueworks.ConnectionTest.Z2MTest do
  use ExUnit.Case, async: true

  alias Hueworks.ConnectionTest.Z2M

  test "returns validation error when host is missing" do
    assert {:error, "Z2M test failed: host is required."} == Z2M.test("", %{})
  end

  test "connects to broker host/port" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)

    accept_task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
    end)

    assert {:ok, "Zigbee2MQTT"} == Z2M.test("127.0.0.1", %{"broker_port" => port})

    Task.await(accept_task, 3_000)
  end
end
