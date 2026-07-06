defmodule Hueworks.ControlCasetaClientTest do
  use ExUnit.Case, async: true

  alias Hueworks.Control.CasetaClient

  defmodule FakeSSL do
    def connect(_host, _port, _opts, _timeout), do: {:ok, :socket}
    def setopts(_socket, _opts), do: Process.get(:setopts_result, :ok)
    def send(_socket, _payload), do: Process.get(:send_result, :ok)

    def recv(_socket, _length, _timeout) do
      response = %{"Header" => %{"StatusCode" => "200 OK", "Url" => "/zone/1"}}
      {:ok, Jason.encode!(response) <> "\r\n"}
    end

    def close(_socket), do: :ok
  end

  test "returns setopts failures instead of waiting for recv timeout" do
    Process.put(:setopts_result, {:error, :closed})

    assert CasetaClient.request(
             "10.0.0.20",
             [],
             %{"Header" => %{"Url" => "/zone/1"}},
             FakeSSL
           ) == {:error, {:ssl_setopts, :closed}}
  end

  test "returns send failures instead of waiting for recv timeout" do
    Process.put(:send_result, {:error, :closed})

    assert CasetaClient.request(
             "10.0.0.20",
             [],
             %{"Header" => %{"Url" => "/zone/1"}},
             FakeSSL
           ) == {:error, {:ssl_send, :closed}}
  end

  test "returns ok when the LEAP response status is successful" do
    assert CasetaClient.request(
             "10.0.0.20",
             [],
             %{"Header" => %{"Url" => "/zone/1"}},
             FakeSSL
           ) == :ok
  end
end
