defmodule Hueworks.Import.Fetch.HomeAssistant.ClientTest do
  use ExUnit.Case, async: true

  alias Hueworks.Import.Fetch.HomeAssistant.Client

  test "auth success releases connection waiters" do
    {:ok, state} = Client.init(%{token: "token"})
    ref = make_ref()

    assert {:ok, waiting} =
             Client.handle_cast({:await_authenticated, ref, self()}, state)

    assert {:ok, authenticated} =
             Client.handle_frame({:text, Jason.encode!(%{"type" => "auth_ok"})}, waiting)

    assert_receive {:ha_authenticated, ^ref, :ok}
    assert authenticated.authenticated
    assert authenticated.auth_waiters == []
  end

  test "auth failure immediately rejects connection and queued request waiters" do
    {:ok, state} = Client.init(%{token: "rejected"})
    auth_ref = make_ref()
    request_ref = make_ref()

    assert {:ok, waiting} =
             Client.handle_cast({:await_authenticated, auth_ref, self()}, state)

    assert {:ok, queued} =
             Client.handle_cast(
               {:request, request_ref, self(), "get_states", %{}, & &1},
               waiting
             )

    payload = %{"type" => "auth_invalid", "message" => "Invalid access token"}
    assert {:close, closed} = Client.handle_frame({:text, Jason.encode!(payload)}, queued)

    assert_receive {:ha_authenticated, ^auth_ref, {:error, :unauthorized}}
    assert_receive {:response, ^request_ref, {:error, :unauthorized}}
    assert closed.auth_waiters == []
    assert closed.queue == []
  end
end
