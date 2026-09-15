defmodule Hueworks.HomeKit.HAPSessionTransport do
  @moduledoc false

  @behaviour ThousandIsland.Transport

  @send_key_key :hap_send_key
  @recv_key_key :hap_recv_key
  @recv_buffer_key :hap_recv_buffer
  @plaintext_buffer_key :hap_plaintext_buffer
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
  # Bandit asks for plaintext byte counts, which say nothing about how many encrypted
  # bytes are on the wire. Once the session is encrypted we read whatever is available,
  # decrypt whole frames, and serve plaintext from a buffer: at most `length` bytes when
  # `length` is positive, everything buffered when it is zero.
  def recv(socket, length, timeout) do
    case Process.get(@recv_key_key) do
      nil -> ThousandIsland.Transports.TCP.recv(socket, length, timeout)
      _recv_key -> recv_plaintext(socket, length, deadline(timeout))
    end
  end

  @doc "Returns and clears plaintext left over from an earlier `recv/3`."
  def pop_plaintext do
    case Process.delete(@plaintext_buffer_key) do
      nil -> <<>>
      plaintext -> plaintext
    end
  end

  defp recv_plaintext(socket, length, deadline) do
    buffered = Process.get(@plaintext_buffer_key, <<>>)

    if satisfied?(buffered, length) do
      {:ok, take_plaintext(buffered, length)}
    else
      with {:ok, timeout} <- remaining_timeout(deadline),
           {:ok, data} <- ThousandIsland.Transports.TCP.recv(socket, 0, timeout),
           {:ok, plaintext} <- decrypt_buffered(data) do
        Process.put(@plaintext_buffer_key, buffered <> plaintext)
        recv_plaintext(socket, length, deadline)
      end
    end
  end

  defp satisfied?(buffered, 0), do: buffered != <<>>
  defp satisfied?(buffered, length), do: byte_size(buffered) >= length

  defp take_plaintext(buffered, 0) do
    Process.delete(@plaintext_buffer_key)
    buffered
  end

  defp take_plaintext(buffered, length) do
    <<head::binary-size(^length), rest::binary>> = buffered

    if rest == <<>> do
      Process.delete(@plaintext_buffer_key)
    else
      Process.put(@plaintext_buffer_key, rest)
    end

    head
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp remaining_timeout(:infinity), do: {:ok, :infinity}

  defp remaining_timeout(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> {:ok, remaining}
      _elapsed -> {:error, :timeout}
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

  @doc "Decrypts a packet that must contain only whole frames."
  def decrypt_if_needed(packet) do
    case Process.get(@recv_key_key) do
      nil ->
        {:ok, packet}

      recv_key ->
        case decrypt_frames(packet, recv_key, []) do
          {:ok, plaintext, <<>>} -> {:ok, plaintext}
          {:ok, _plaintext, _partial} -> {:error, :incomplete_encrypted_frame}
          {:error, _reason} = error -> error
        end
    end
  end

  @doc """
  Decrypts the whole frames in `packet`, carrying any trailing partial frame over to the
  next call in the connection process. Returns `{:ok, <<>>}` when no frame is complete yet.
  """
  def decrypt_buffered(packet) do
    case Process.get(@recv_key_key) do
      nil ->
        {:ok, packet}

      recv_key ->
        buffer = Process.get(@recv_buffer_key, <<>>) <> packet

        case decrypt_frames(buffer, recv_key, []) do
          {:ok, plaintext, <<>>} ->
            Process.delete(@recv_buffer_key)
            {:ok, plaintext}

          {:ok, plaintext, partial} ->
            Process.put(@recv_buffer_key, partial)
            {:ok, plaintext}

          {:error, _reason} = error ->
            Process.delete(@recv_buffer_key)
            error
        end
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

  defp decrypt_frames(
         <<length::integer-size(16)-little, encrypted_data::binary-size(length),
           tag::binary-size(16), rest::binary>>,
         recv_key,
         acc
       ) do
    counter = Process.get(:recv_counter, 0)
    nonce = pad_counter(counter)
    length_aad = <<length::integer-size(16)-little>>

    case HAP.Crypto.ChaCha20.decrypt_and_verify(
           encrypted_data <> tag,
           recv_key,
           nonce,
           length_aad
         ) do
      {:ok, data} ->
        Process.put(:recv_counter, counter + 1)
        decrypt_frames(rest, recv_key, [data | acc])

      {:error, _reason} = error ->
        error
    end
  end

  defp decrypt_frames(partial, _recv_key, acc) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), partial}
  end

  defp pad_counter(counter) do
    <<0::32, counter::integer-size(64)-little>>
  end
end
