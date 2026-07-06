defmodule Hueworks.Control.CasetaClient do
  @moduledoc false

  require Logger

  @bridge_port 8081

  def request(host, ssl_opts, payload, ssl_module \\ :ssl) do
    with {:ok, socket} <-
           ssl_module.connect(String.to_charlist(host), @bridge_port, ssl_opts, 5000) do
      result = request_on_socket(ssl_module, socket, payload)
      ssl_module.close(socket)
      result
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_on_socket(ssl_module, socket, payload) do
    with :ok <- set_socket_opts(ssl_module, socket),
         :ok <- send_payload(ssl_module, socket, payload) do
      payload
      |> get_in(["Header", "Url"])
      |> then(&read_until_match(ssl_module, socket, &1, 5000))
    end
  end

  defp set_socket_opts(ssl_module, socket) do
    case ssl_module.setopts(socket, active: false, packet: :line) do
      :ok -> :ok
      {:error, reason} -> {:error, {:ssl_setopts, reason}}
    end
  end

  defp send_payload(ssl_module, socket, payload) do
    case ssl_module.send(socket, Jason.encode!(payload) <> "\r\n") do
      :ok -> :ok
      {:error, reason} -> {:error, {:ssl_send, reason}}
    end
  end

  defp read_until_match(ssl_module, socket, url, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_read_until_match(ssl_module, socket, url, deadline)
  end

  defp do_read_until_match(ssl_module, socket, url, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      {:error, :timeout}
    else
      case ssl_module.recv(socket, 0, remaining) do
        {:ok, data} ->
          data
          |> IO.iodata_to_binary()
          |> String.split("\r\n", trim: true)
          |> Enum.find_value(:continue, fn line ->
            case decode_line(line) do
              {:ok, decoded} ->
                header = decoded["Header"] || %{}
                status = header["StatusCode"]
                resp_url = header["Url"]

                if is_binary(status) and resp_url == url do
                  Logger.debug("Caseta LEAP response: #{line}")

                  if String.starts_with?(status, "2") do
                    :ok
                  else
                    {:error, {:http_error, status, line}}
                  end
                else
                  :continue
                end

              {:error, _reason} ->
                :continue
            end
          end)
          |> case do
            :continue -> do_read_until_match(ssl_module, socket, url, deadline)
            other -> other
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, reason}
    end
  end
end
