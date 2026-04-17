defmodule Hueworks.HomeAssistant.Export.HandlerTest do
  use ExUnit.Case, async: true

  alias Hueworks.HomeAssistant.Export.Handler

  test "init normalizes topic filters into subscriptions" do
    assert {:ok, state} = Handler.init([self(), "client-1", ["one/topic", "two/topic"]])

    assert state.server == self()
    assert state.client_id == "client-1"
    assert state.subscriptions == [{"one/topic", 0}, {"two/topic", 0}]
    refute state.subscribed?
  end

  test "connection down clears subscribed state" do
    {:ok, state} = Handler.init([self(), "client-1", ["one/topic"]])

    assert {:ok, updated} = Handler.connection(:down, %{state | subscribed?: true})
    refute updated.subscribed?
  end

  test "handle_message forwards MQTT messages to the export server" do
    {:ok, state} = Handler.init([self(), "client-1", ["one/topic"]])

    assert {:ok, ^state} = Handler.handle_message(["a", "b"], "{\"x\":1}", state)
    assert_received {:mqtt_message, ["a", "b"], "{\"x\":1}"}
  end
end
