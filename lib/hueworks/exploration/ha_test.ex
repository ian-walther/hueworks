defmodule Hueworks.Exploration.HATest do
  @moduledoc """
  Quick throwaway module to test Home Assistant WebSocket API.
  """
  use WebSockex

  # State structure: %{msg_id: integer, pending: map, token: string}

  @doc """
  Connect to Home Assistant and authenticate.

  ## Examples

  {:ok, pid} = Hueworks.Exploration.HATest.connect("192.168.1.41", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI1Y2MyNTVmZDU0OTE0ZWJmYjNmMjVjZGZmY2I2M2QxOSIsImlhdCI6MTc2ODQzNDc1NywiZXhwIjoyMDgzNzk0NzU3fQ.0Acp4FYb8GTxvC5G50dV4jwgbIWQedHP97zNM6_cJCE")
  """
  def connect(host, token) do
    url = "ws://#{host}:8123/api/websocket"

    state = %{
      msg_id: 1,
      pending: %{},
      token: token,
      authenticated: false
    }

    case WebSockex.start_link(url, __MODULE__, state) do
      {:ok, pid} ->
        # Wait for authentication to complete
        Process.sleep(500)
        {:ok, pid}

      {:error, reason} ->
        IO.puts("Connection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Turn on a light with optional parameters.

  ## Examples

      turn_on(pid, "light.living_room", brightness: 255)
      turn_on(pid, "light.strip", brightness: 200, rgb_color: [255, 0, 0])
  """
  def turn_on(pid, entity_id, opts \\ []) do
    service_data =
      opts
      |> Enum.into(%{entity_id: entity_id})

    call_service(pid, "light", "turn_on", service_data)
  end

  @doc """
  Turn off a light.

  ## Examples

      turn_off(pid, "light.living_room")
  """
  def turn_off(pid, entity_id) do
    call_service(pid, "light", "turn_off", %{entity_id: entity_id})
  end

  @doc """
  Get the current state of a specific entity.

  ## Examples

      get_state(pid, "light.living_room")
  """
  def get_state(pid, entity_id) do
    request(pid, "get_states", %{}, fn states ->
      Enum.find(states, fn state ->
        state["entity_id"] == entity_id
      end)
    end)
  end

  @doc """
  List all light entities.

  ## Examples

      list_lights(pid)
  """
  def list_lights(pid) do
    request(pid, "get_states", %{}, fn states ->
      states
      |> Enum.filter(fn state ->
        String.starts_with?(state["entity_id"], "light.")
      end)
      |> Enum.map(fn state ->
        %{
          entity_id: state["entity_id"],
          state: state["state"],
          brightness: get_in(state, ["attributes", "brightness"]),
          friendly_name: get_in(state, ["attributes", "friendly_name"])
        }
      end)
    end)
  end

  @doc """
  Simple test function to run in IEx.

  Update the host and token, then run:

      HATest.test()
  """
  def test do
    # UPDATE THESE VALUES
    host = "192.168.1.100"
    token = "your-long-lived-token-here"

    IO.puts("\n=== Connecting to Home Assistant ===")
    {:ok, pid} = connect(host, token)

    IO.puts("\n=== Listing lights ===")
    lights = list_lights(pid)

    Enum.each(lights, fn light ->
      IO.puts("#{light.entity_id} | #{light.state} | #{light.friendly_name}")
    end)

    # Pick first light for testing
    if length(lights) > 0 do
      test_light = hd(lights).entity_id
      IO.puts("\n=== Testing with #{test_light} ===")

      IO.puts("Getting state...")
      state = get_state(pid, test_light)
      IO.inspect(state, label: "Current state")

      IO.puts("\nTurning on at 50% brightness...")
      turn_on(pid, test_light, brightness: 128)
      Process.sleep(2000)

      IO.puts("Turning off...")
      turn_off(pid, test_light)
      Process.sleep(2000)

      IO.puts("\nTest complete!")
    end

    {:ok, pid}
  end

  # Private API

  defp call_service(pid, domain, service, service_data) do
    request(pid, "call_service", %{
      domain: domain,
      service: service,
      service_data: service_data
    })
  end

  defp request(pid, type, params, transform_fn \\ & &1) do
    ref = make_ref()

    WebSockex.cast(pid, {:request, ref, self(), type, params, transform_fn})

    receive do
      {:response, ^ref, result} -> result
    after
      5000 -> {:error, :timeout}
    end
  end

  # WebSockex Callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    IO.puts("Connected to Home Assistant WebSocket")
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"type" => "auth_required"}} ->
        IO.puts("Authentication required, sending token...")
        auth_msg = Jason.encode!(%{type: "auth", access_token: state.token})
        {:reply, {:text, auth_msg}, state}

      {:ok, %{"type" => "auth_ok"}} ->
        IO.puts("Authentication successful!")
        {:ok, %{state | authenticated: true}}

      {:ok, %{"type" => "auth_invalid", "message" => message}} ->
        IO.puts("Authentication failed: #{message}")
        {:close, state}

      {:ok, %{"type" => "result", "id" => msg_id, "success" => true, "result" => result}} ->
        handle_result(msg_id, result, state)

      {:ok, %{"type" => "result", "id" => msg_id, "success" => false, "error" => error}} ->
        handle_error(msg_id, error, state)

      {:ok, %{"type" => "event"}} ->
        # Ignore events for now
        {:ok, state}

      {:ok, decoded} ->
        IO.inspect(decoded, label: "Unhandled message")
        {:ok, state}

      {:error, reason} ->
        IO.puts("Failed to decode message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl WebSockex
  def handle_cast({:request, ref, caller, type, params, transform_fn}, state) do
    msg_id = state.msg_id
    pending = Map.put(state.pending, msg_id, {ref, caller, transform_fn})

    message =
      params
      |> Map.put(:type, type)
      |> Map.put(:id, msg_id)
      |> Jason.encode!()

    {:reply, {:text, message}, %{state | msg_id: msg_id + 1, pending: pending}}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    IO.puts("Disconnected: #{inspect(reason)}")
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, _state) do
    IO.puts("WebSocket terminated: #{inspect(reason)}")
    :ok
  end

  # Helpers

  defp handle_result(msg_id, result, state) do
    case Map.pop(state.pending, msg_id) do
      {{ref, caller, transform_fn}, pending} ->
        transformed = transform_fn.(result)
        send(caller, {:response, ref, {:ok, transformed}})
        {:ok, %{state | pending: pending}}

      {nil, _pending} ->
        IO.inspect(result, label: "Unmatched result for msg_id #{msg_id}")
        {:ok, state}
    end
  end

  defp handle_error(msg_id, error, state) do
    case Map.pop(state.pending, msg_id) do
      {{ref, caller, _transform_fn}, pending} ->
        send(caller, {:response, ref, {:error, error}})
        {:ok, %{state | pending: pending}}

      {nil, _pending} ->
        IO.inspect(error, label: "Unmatched error for msg_id #{msg_id}")
        {:ok, state}
    end
  end
end
