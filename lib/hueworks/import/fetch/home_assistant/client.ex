defmodule Hueworks.Import.Fetch.HomeAssistant.Client do
  @moduledoc false

  use WebSockex

  alias Hueworks.HomeAssistant.Host

  require Logger

  @default_state %{token: nil, authenticated: false, next_id: 1, pending: %{}, queue: []}

  def connect(host, token) do
    url = "ws://#{Host.normalize(host)}/api/websocket"
    state = %{@default_state | token: token}
    WebSockex.start_link(url, __MODULE__, state)
  end

  def init(state) do
    {:ok, normalize_state(state)}
  end

  @impl true
  def handle_connect(_conn, state) do
    {:ok, normalize_state(state)}
  end

  @impl true
  def handle_cast({:request, ref, from, type, params, fun}, state) do
    state = normalize_state(state)

    if state.authenticated do
      {frame, state} = build_request_frame(state, ref, from, type, params, fun)
      {:reply, frame, state}
    else
      queue = state.queue ++ [{ref, from, type, params, fun}]
      {:ok, %{state | queue: queue}}
    end
  end

  @impl true
  def handle_frame({:text, message}, state) do
    state = normalize_state(state)

    case Jason.decode(message) do
      {:ok, %{"type" => "auth_required"}} ->
        auth = %{"type" => "auth", "access_token" => state.token}
        {:reply, {:text, Jason.encode!(auth)}, state}

      {:ok, %{"type" => "auth_ok"}} ->
        state = %{state | authenticated: true}
        send_next_queued(state)

      {:ok, %{"type" => "auth_invalid"} = payload} ->
        Logger.error("Home Assistant auth failed: #{inspect(payload)}")
        {:ok, state}

      {:ok, %{"type" => "result", "id" => id} = payload} ->
        {pending, pending_map} = Map.pop(state.pending, id)

        state =
          case pending do
            {ref, from, fun} ->
              result = result_from_payload(payload)
              send(from, {:response, ref, fun.(result)})
              %{state | pending: pending_map}

            nil ->
              %{state | pending: pending_map}
          end

        send_next_queued(state)

      {:ok, _payload} ->
        {:ok, state}

      {:error, _reason} ->
        {:ok, state}
    end
  end

  defp send_next_queued(state) do
    case state.queue do
      [next | rest] ->
        {frame, state} = build_request_frame(%{state | queue: rest}, next)
        {:reply, frame, state}

      [] ->
        {:ok, state}
    end
  end

  defp build_request_frame(state, {ref, from, type, params, fun}) do
    build_request_frame(state, ref, from, type, params, fun)
  end

  defp build_request_frame(state, ref, from, type, params, fun) do
    id = state.next_id
    payload = params |> Map.new() |> Map.merge(%{"id" => id, "type" => type})
    frame = {:text, Jason.encode!(payload)}
    pending = Map.put(state.pending, id, {ref, from, fun})
    {frame, %{state | next_id: id + 1, pending: pending}}
  end

  defp result_from_payload(%{"success" => true, "result" => result}), do: {:ok, result}
  defp result_from_payload(%{"success" => false, "error" => error}), do: {:error, error}
  defp result_from_payload(_payload), do: {:error, :invalid_response}

  defp normalize_state(state) when is_map(state) do
    Map.merge(@default_state, state)
  end

  defp normalize_state(_state), do: @default_state
end
