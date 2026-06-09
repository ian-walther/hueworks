defmodule Hueworks.HomeKit.HAPSessionTransport do
  @moduledoc false

  @behaviour ThousandIsland.Transport

  @send_key_key :hap_send_key
  @recv_key_key :hap_recv_key
  @max_encrypted_payload_size 1_024

  @impl ThousandIsland.Transport
  defdelegate listen(port, options), to: HAP.HAPSessionTransport

  @impl ThousandIsland.Transport
  defdelegate accept(listener_socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate handshake(socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate upgrade(socket, options), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate controlling_process(socket, pid), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  def recv(socket, length, timeout) do
    case ThousandIsland.Transports.TCP.recv(socket, length, timeout) do
      {:ok, data} -> decrypt_if_needed(data)
      other -> other
    end
  end

  @impl ThousandIsland.Transport
  def send(socket, data) do
    case Process.get(@send_key_key) do
      nil ->
        ThousandIsland.Transports.TCP.send(socket, data)

      send_key ->
        ThousandIsland.Transports.TCP.send(socket, encrypted_frames(data, send_key))
    end
  end

  @impl ThousandIsland.Transport
  defdelegate sendfile(socket, filename, offset, length), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate getopts(socket, options), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate setopts(socket, options), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate shutdown(socket, way), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate close(socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate sockname(socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate peername(socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate peercert(socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate secure?(), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate getstat(socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate negotiated_protocol(socket), to: ThousandIsland.Transports.TCP

  @impl ThousandIsland.Transport
  defdelegate connection_information(socket), to: ThousandIsland.Transports.TCP

  def encrypted_frames(data, send_key) do
    data
    |> IO.iodata_to_binary()
    |> chunks()
    |> Enum.map(&encrypt_frame(&1, send_key))
  end

  def decrypt_if_needed(packet) do
    case Process.get(@recv_key_key) do
      nil -> {:ok, packet}
      recv_key -> decrypt_frames(packet, recv_key, [])
    end
  end

  defp chunks(<<>>), do: []

  defp chunks(data), do: chunks(data, [])

  defp chunks(<<>>, acc), do: Enum.reverse(acc)

  defp chunks(data, acc) when byte_size(data) <= @max_encrypted_payload_size do
    chunks(<<>>, [data | acc])
  end

  defp chunks(
         <<chunk::binary-size(@max_encrypted_payload_size), rest::binary>>,
         acc
       ) do
    chunks(rest, [chunk | acc])
  end

  defp encrypt_frame(data, send_key) do
    counter = Process.get(:send_counter, 0)
    nonce = pad_counter(counter)
    length_aad = <<byte_size(data)::integer-size(16)-little>>

    {:ok, encrypted_data_and_tag} =
      HAP.Crypto.ChaCha20.encrypt_and_tag(data, send_key, nonce, length_aad)

    Process.put(:send_counter, counter + 1)
    length_aad <> encrypted_data_and_tag
  end

  defp decrypt_frames(<<>>, _recv_key, acc) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp decrypt_frames(
         <<length::integer-size(16)-little, encrypted_data::binary-size(length),
           tag::binary-size(16), rest::binary>>,
         recv_key,
         acc
       ) do
    counter = Process.get(:recv_counter, 0)
    nonce = pad_counter(counter)
    length_aad = <<length::integer-size(16)-little>>

    with {:ok, data} <-
           HAP.Crypto.ChaCha20.decrypt_and_verify(
             encrypted_data <> tag,
             recv_key,
             nonce,
             length_aad
           ) do
      Process.put(:recv_counter, counter + 1)
      decrypt_frames(rest, recv_key, [data | acc])
    end
  end

  defp decrypt_frames(_partial, _recv_key, _acc), do: {:error, :incomplete_encrypted_frame}

  defp pad_counter(counter) do
    <<0::32, counter::integer-size(64)-little>>
  end
end
