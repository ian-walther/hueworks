defmodule Hueworks.ConnectionTest.CasetaTest do
  use ExUnit.Case, async: true

  alias Hueworks.ConnectionTest.Caseta

  @credentials %{
    caseta_cert: "/tmp/client.crt",
    caseta_key: "/tmp/client.key",
    caseta_cacert: "/tmp/ca.crt"
  }

  test "performs a safe LEAP read after TLS authentication" do
    assert {:ok, "Caseta Bridge"} =
             Caseta.test("caseta.local", @credentials, __MODULE__.SuccessfulSSL)

    assert_receive {:leap_request,
                    %{
                      "CommuniqueType" => "ReadRequest",
                      "Header" => %{"Url" => "/device"}
                    }}
  end

  test "rejects a TLS endpoint that cannot answer a LEAP request" do
    assert {:error, message} =
             Caseta.test("caseta.local", @credentials, __MODULE__.FailedReadSSL)

    assert message =~ "Caseta test failed"
    assert message =~ "LEAP"
  end

  test "requires all staged credentials" do
    assert {:error, "Caseta test failed: missing required credential files."} =
             Caseta.test("caseta.local", %{}, __MODULE__.SuccessfulSSL)
  end

  defmodule SuccessfulSSL do
    def connect(_host, 8081, _opts, 5_000), do: {:ok, :socket}
    def setopts(:socket, active: false, packet: :line), do: :ok

    def send(:socket, payload) do
      decoded = payload |> IO.iodata_to_binary() |> String.trim() |> Jason.decode!()
      Kernel.send(self(), {:leap_request, decoded})
      :ok
    end

    def recv(:socket, 0, _timeout) do
      {:ok,
       Jason.encode!(%{
         "Header" => %{"Url" => "/device", "StatusCode" => "200 OK"},
         "Body" => %{"Devices" => []}
       }) <> "\r\n"}
    end

    def close(:socket), do: :ok
  end

  defmodule FailedReadSSL do
    def connect(_host, 8081, _opts, 5_000), do: {:ok, :socket}
    def setopts(:socket, active: false, packet: :line), do: :ok
    def send(:socket, _payload), do: :ok
    def recv(:socket, 0, _timeout), do: {:error, :closed}
    def close(:socket), do: :ok
  end
end
