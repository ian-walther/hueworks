defmodule Hueworks.ConnectionTest.Caseta do
  @moduledoc false

  alias Hueworks.Control.CasetaLeap
  alias Hueworks.Schemas.Bridge
  alias Hueworks.Schemas.Bridge.Credentials

  @test_url "/device"

  def test(host, staged), do: test(host, staged, :ssl)

  def test(
        host,
        %{caseta_cert: cert_path, caseta_key: key_path, caseta_cacert: cacert_path},
        ssl_module
      ) do
    bridge = %Bridge{
      host: host,
      credentials: %Credentials{
        cert_path: cert_path,
        key_path: key_path,
        cacert_path: cacert_path
      }
    }

    case CasetaLeap.connect(bridge, ssl_module) do
      {:ok, socket} ->
        try do
          validate_leap(socket, ssl_module)
        after
          ssl_module.close(socket)
        end

      {:error, reason} ->
        {:error, "Caseta test failed: #{inspect(reason)}"}
    end
  end

  def test(_host, _staged, _ssl_module) do
    {:error, "Caseta test failed: missing required credential files."}
  end

  defp validate_leap(socket, ssl_module) do
    request = %{
      "CommuniqueType" => "ReadRequest",
      "Header" => %{"Url" => @test_url}
    }

    with :ok <- CasetaLeap.set_socket_opts(ssl_module, socket),
         :ok <- CasetaLeap.send_request(ssl_module, socket, request),
         {:ok, response} <-
           CasetaLeap.read_until_match(ssl_module, socket, @test_url, 5_000, :message),
         :ok <- require_success(response) do
      {:ok, "Caseta Bridge"}
    else
      {:error, reason} -> {:error, "Caseta test failed: LEAP read failed: #{inspect(reason)}"}
    end
  end

  defp require_success(%{"Header" => %{"StatusCode" => status}}) when is_binary(status) do
    if String.starts_with?(status, "2"), do: :ok, else: {:error, {:leap_status, status}}
  end

  defp require_success(_response), do: {:error, :missing_leap_status}
end
