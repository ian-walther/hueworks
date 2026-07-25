defmodule Hueworks.ConnectionTest.HueTest do
  use ExUnit.Case, async: true

  alias Hueworks.ConnectionTest.Hue

  test "returns the normalized bridge identity from a successful config response" do
    assert {:ok, %{name: "Office Hue", external_id: "001788fffe111111"}} =
             Hue.test("192.168.1.10", "api-key", http: __MODULE__.HttpStub)
  end

  test "translates a refused connection without exposing raw transport vocabulary" do
    assert {:error, message} =
             Hue.test("192.168.1.10", "api-key", http: __MODULE__.RefusedHttp)

    assert message =~ "Hue connection was refused"
    refute message =~ "econnrefused"
  end

  defmodule HttpStub do
    def get("http://192.168.1.10/api/api-key/config", [], recv_timeout: 5_000) do
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: Jason.encode!(%{"name" => "Office Hue", "bridgeid" => "001788FFFE111111"})
       }}
    end
  end

  defmodule RefusedHttp do
    def get(_url, _headers, _opts), do: {:error, %HTTPoison.Error{reason: :econnrefused}}
  end
end
