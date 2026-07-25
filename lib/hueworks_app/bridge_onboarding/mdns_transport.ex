defmodule Hueworks.BridgeOnboarding.MdnsTransport do
  @moduledoc false

  import MdnsLite.DNS

  @multicast_address {224, 0, 0, 251}
  @multicast_port 5_353

  def query(query, response_timeout, opts \\ []) do
    backend = Keyword.get(opts, :backend, __MODULE__.UdpBackend)
    payload = MdnsLite.Client.encode(query, unicast: true)

    case backend.open() do
      {:ok, socket} ->
        try do
          with :ok <- backend.send(socket, @multicast_address, @multicast_port, payload) do
            deadline = System.monotonic_time(:millisecond) + response_timeout
            collect_responses(backend, socket, deadline, %{answer: [], additional: []})
          end
        after
          backend.close(socket)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_responses(backend, socket, deadline, response) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining == 0 do
      {:ok, response}
    else
      case backend.recv(socket, remaining) do
        {:ok, {_address, _port, packet}} ->
          response = merge_packet(response, packet)
          collect_responses(backend, socket, deadline, response)

        {:error, :timeout} ->
          {:ok, response}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp merge_packet(response, packet) do
    case MdnsLite.DNS.decode(packet) do
      {:ok, message} ->
        %{
          answer: response.answer ++ dns_rec(message, :anlist),
          additional: response.additional ++ dns_rec(message, :arlist)
        }

      {:error, _reason} ->
        response
    end
  end

  defmodule UdpBackend do
    @moduledoc false

    def open, do: :gen_udp.open(0, [:binary, active: false])
    def send(socket, address, port, payload), do: :gen_udp.send(socket, address, port, payload)
    def recv(socket, timeout), do: :gen_udp.recv(socket, 0, timeout)
    def close(socket), do: :gen_udp.close(socket)
  end
end
