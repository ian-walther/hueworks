defmodule Hueworks.Control.CasetaLeap do
  @moduledoc false

  require Logger

  alias Hueworks.Schemas.Bridge

  @bridge_port 8081

  def ssl_opts_for(%Bridge{} = bridge) do
    credentials = Bridge.credentials_struct(bridge)
    cert_path = credentials.cert_path
    key_path = credentials.key_path
    cacert_path = credentials.cacert_path

    if Enum.any?([cert_path, key_path, cacert_path], &invalid_credential?/1) do
      {:error, :missing_credentials}
    else
      {:ok,
       [
         certfile: cert_path,
         keyfile: key_path,
         cacertfile: cacert_path,
         # Lutron LEAP bridges use client cert auth with self-signed LAN certs.
         verify: :verify_none,
         versions: [:"tlsv1.2"]
       ]}
    end
  end

  def connect(%Bridge{} = bridge, ssl_module \\ :ssl) do
    with {:ok, ssl_opts} <- ssl_opts_for(bridge) do
      ssl_module.connect(String.to_charlist(bridge.host), @bridge_port, ssl_opts, 5000)
    end
  end

  def set_socket_opts(ssl_module, socket, opts \\ [active: false, packet: :line]) do
    case ssl_module.setopts(socket, opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:ssl_setopts, reason}}
    end
  end

  def send_request(ssl_module, socket, payload) do
    case ssl_module.send(socket, Jason.encode!(payload) <> "\r\n") do
      :ok -> :ok
      {:error, reason} -> {:error, {:ssl_send, reason}}
    end
  end

  def read_until_match(socket, url, timeout, mode) when mode in [:message, :status] do
    read_until_match(:ssl, socket, url, timeout, mode)
  end

  def read_until_match(ssl_module, socket, url, timeout, mode)
      when mode in [:message, :status] do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_read_until_match(ssl_module, socket, url, deadline, mode)
  end

  def decode_message(""), do: {:error, :empty}

  def decode_message(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, :invalid}
    end
  end

  def invalid_credential?(value) do
    not is_binary(value) or value == "" or value == "CHANGE_ME"
  end

  defp do_read_until_match(ssl_module, socket, url, deadline, mode) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      {:error, :timeout}
    else
      case ssl_module.recv(socket, 0, remaining) do
        {:ok, data} ->
          data
          |> IO.iodata_to_binary()
          |> String.split("\r\n", trim: true)
          |> Enum.find_value(:continue, &match_line(&1, url, mode))
          |> case do
            :continue -> do_read_until_match(ssl_module, socket, url, deadline, mode)
            other -> other
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp match_line(line, url, mode) do
    case decode_message(line) do
      {:ok, %{"Header" => %{"Url" => ^url}} = decoded} ->
        response_for_mode(decoded, line, mode)

      _ ->
        nil
    end
  end

  defp response_for_mode(decoded, _line, :message), do: {:ok, decoded}

  defp response_for_mode(%{"Header" => header}, line, :status) do
    case header["StatusCode"] do
      status when is_binary(status) ->
        Logger.debug("Caseta LEAP response: #{line}")

        if String.starts_with?(status, "2") do
          :ok
        else
          {:error, {:http_error, status, line}}
        end

      _ ->
        nil
    end
  end
end
