defmodule Hueworks.ControlCasetaLeapTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.CasetaLeap

  defmodule FakeSSL do
    def recv(_socket, _length, _timeout) do
      {:ok, Process.get(:recv_payload)}
    end
  end

  test "message mode returns the decoded response matching the requested URL" do
    Process.put(
      :recv_payload,
      [
        Jason.encode!(%{"Header" => %{"Url" => "/ignored"}}),
        "\r\n",
        Jason.encode!(%{"Header" => %{"Url" => "/zone/status"}, "Body" => %{"ok" => true}}),
        "\r\n"
      ]
    )

    assert {:ok, decoded} =
             CasetaLeap.read_until_match(FakeSSL, :socket, "/zone/status", 5000, :message)

    assert decoded["Body"] == %{"ok" => true}
  end

  test "status mode returns ok for successful matching responses" do
    Process.put(
      :recv_payload,
      Jason.encode!(%{"Header" => %{"Url" => "/zone/1", "StatusCode" => "200 OK"}}) <> "\r\n"
    )

    assert :ok = CasetaLeap.read_until_match(FakeSSL, :socket, "/zone/1", 5000, :status)
  end

  test "status mode returns http errors for failed matching responses" do
    payload =
      Jason.encode!(%{"Header" => %{"Url" => "/zone/1", "StatusCode" => "404 Not Found"}})

    Process.put(:recv_payload, payload <> "\r\n")

    assert {:error, {:http_error, "404 Not Found", ^payload}} =
             CasetaLeap.read_until_match(FakeSSL, :socket, "/zone/1", 5000, :status)
  end
end
