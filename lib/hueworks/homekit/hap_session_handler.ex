defmodule Hueworks.HomeKit.HAPSessionHandler do
  @moduledoc false

  use ThousandIsland.Handler

  def push(pid, data) do
    GenServer.cast(pid, {:push, data})
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    {:ok, data} = Hueworks.HomeKit.HAPSessionTransport.decrypt_if_needed(data)
    Bandit.HTTP1.Handler.handle_data(data, socket, state)
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
  def handle_info({:plug_conn, :sent}, state) do
    Bandit.HTTP1.Handler.handle_info({:plug_conn, :sent}, state)
  end

  def handle_info({:EXIT, pid, :normal}, state) when is_pid(pid) do
    Bandit.HTTP1.Handler.handle_info({:EXIT, pid, :normal}, state)
  end
end
