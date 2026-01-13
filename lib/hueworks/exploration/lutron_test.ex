defmodule Hueworks.Exploration.LutronTest do
  @moduledoc """
  Quick throwaway module to test Lutron LEAP connection
  """

  @bridge_ip "192.168.1.123"
  @bridge_port 8081

  @cert_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123.crt"
  @key_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123.key"
  @cacert_path "/Users/ianwalther/.config/pylutron_caseta/192.168.1.123-bridge.crt"

  def connect do
    ssl_opts = [
      certfile: @cert_path,
      keyfile: @key_path,
      cacertfile: @cacert_path,
      verify: :verify_none,
      versions: [:"tlsv1.2"]
    ]

    case :ssl.connect(
           String.to_charlist(@bridge_ip),
           @bridge_port,
           ssl_opts,
           5000
         ) do
      {:ok, socket} ->
        IO.puts("Connected to Lutron bridge!")
        {:ok, socket}

      {:error, reason} ->
        IO.puts("Connection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def subscribe_to_buttons(socket) do
    message =
      Jason.encode!(%{
        "CommuniqueType" => "SubscribeRequest",
        "Header" => %{"Url" => "/button"}
      })

    :ssl.send(socket, message <> "\r\n")
  end

  def subscribe_to_all(socket) do
    subscriptions = [
      "/device",
      # This is the key one!
      "/button/status/event",
      "/zone/status",
      "/occupancygroup/status"
    ]

    Enum.each(subscriptions, fn url ->
      message =
        Jason.encode!(%{
          "CommuniqueType" => "SubscribeRequest",
          "Header" => %{"Url" => url}
        })

      :ssl.send(socket, message <> "\r\n")
      Process.sleep(100)
    end)
  end

  def read_initial_messages(socket) do
    :ssl.setopts(socket, [{:active, false}])

    case :ssl.recv(socket, 0, 5000) do
      {:ok, data} ->
        IO.puts("Initial message: #{data}")
        read_initial_messages(socket)

      {:error, :timeout} ->
        IO.puts("No more initial messages")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def listen(socket) do
    # Set socket to passive mode
    :ssl.setopts(socket, [{:active, false}])

    case :ssl.recv(socket, 0, 10000) do
      {:ok, data} ->
        IO.puts("Received: #{data}")
        listen(socket)

      {:error, :timeout} ->
        IO.puts("Timeout, listening again...")
        listen(socket)

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end

  def test_async() do
    {:ok, socket} = connect()
    # Don't read initial messages separately!
    subscribe_to_all(socket)

    # Start listening immediately - it will catch the subscription responses
    task = Task.async(fn -> listen(socket) end)

    IO.puts("Listening in background, press some Pico buttons!")
    {:ok, task}
  end

  def test_async_debug() do
    {:ok, socket} = connect()

    # Subscribe and immediately start listening to see the responses
    Task.async(fn ->
      :ssl.setopts(socket, [{:active, false}])

      # Send subscriptions
      subscribe_to_all(socket)

      # Listen for subscription responses
      IO.puts("\n=== SUBSCRIPTION RESPONSES ===")

      Enum.each(1..4, fn _ ->
        case :ssl.recv(socket, 0, 5000) do
          {:ok, data} ->
            IO.puts("Response: #{data}\n")

          {:error, reason} ->
            IO.puts("Error: #{inspect(reason)}")
        end
      end)

      IO.puts("\n=== NOW LISTENING FOR BUTTON EVENTS - PRESS A PICO ===\n")
      listen(socket)
    end)
    |> then(fn task ->
      IO.puts("Started, press a Pico button now!")
      {:ok, task}
    end)
  end
end

# Kill it with:
# Task.shutdown(task, :brutal_kill)
