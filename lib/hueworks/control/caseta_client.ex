defmodule Hueworks.Control.CasetaClient do
  @moduledoc false

  require Logger

  @bridge_port 8081

  def request(host, ssl_opts, payload) do
    with {:ok, socket} <- :ssl.connect(String.to_charlist(host), @bridge_port, ssl_opts, 5000) do
      :ssl.setopts(socket, active: false, packet: :line)
      :ssl.send(socket, Jason.encode!(payload) <> "\r\n")
      url = get_in(payload, ["Header", "Url"])
      result = read_until_match(socket, url, 5000)
      :ssl.close(socket)
      result
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_until_match(socket, url, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_read_until_match(socket, url, deadline)
  end

  defp do_read_until_match(socket, url, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    if remaining == 0 do
      {:error, :timeout}
    else
      case :ssl.recv(socket, 0, remaining) do
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
            :continue -> do_read_until_match(socket, url, deadline)
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
