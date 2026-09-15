defmodule Hueworks.HomeKit.HAPSessionHandler do
  @moduledoc false
  # Thousand Island handler for HAP sessions. Decrypts inbound frames (buffering partial
  # frames across reads) before handing requests to Bandit, and pushes HAP EVENT messages
  # that the hap library casts to the connection process.

  use ThousandIsland.Handler

  alias Hueworks.HomeKit.HAPSessionTransport

  def push(pid, data) do
    GenServer.cast(pid, {:push, data})
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    case HAPSessionTransport.decrypt_buffered(data) do
      {:ok, plaintext} ->
        case HAPSessionTransport.pop_plaintext() <> plaintext do
          <<>> -> {:continue, state}
          request -> Bandit.HTTP1.Handler.handle_data(request, socket, state)
        end

      {:error, reason} ->
        {:error, {:hap_decrypt_failed, reason}, state}
    end
  end

  @impl GenServer
  def handle_cast({:push, data}, {socket, state}) do
    data = Jason.encode!(data)

    headers = %{
      "content-length" => data |> byte_size() |> to_string(),
      "content-type" => "application/hap+json"
    }

    to_send = [
      "EVENT/1.0 200 OK\r\n",
      Enum.map(headers, fn {key, value} -> [key, ": ", value, "\r\n"] end),
      "\r\n",
      data
    ]

    ThousandIsland.Socket.send(socket, to_send)

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(message, {%ThousandIsland.Socket{} = socket, state}) do
    Bandit.HTTP1.Handler.handle_info(message, {socket, state})
  end
end
