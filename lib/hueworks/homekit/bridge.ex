defmodule Hueworks.HomeKit.Bridge do
  @moduledoc false

  use GenServer
  require Logger

  alias Hueworks.ActiveScenes
  alias Hueworks.HomeKit.AccessoryGraph
  alias Phoenix.PubSub

  @control_topic "control_state"

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def reload, do: maybe_cast(:reload)

  def put_change_token(opts, change_token) when is_list(opts) do
    maybe_cast({:put_change_token, token_key(opts), change_token})
  end

  def status do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, :status)
      _ -> %{running?: false, topology_hash: nil}
    end
  end

  @impl true
  def init(_opts) do
    PubSub.subscribe(Hueworks.PubSub, @control_topic)
    PubSub.subscribe(Hueworks.PubSub, ActiveScenes.topic())

    {:ok, %{hap_pid: nil, topology_hash: nil, change_tokens: %{}}, {:continue, :reload}}
  end

  @impl true
  def handle_continue(:reload, state), do: {:noreply, rebuild(state)}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{running?: is_pid(state.hap_pid), topology_hash: state.topology_hash}, state}
  end

  @impl true
  def handle_cast(:reload, state), do: {:noreply, rebuild(state)}

  def handle_cast({:put_change_token, key, change_token}, state) do
    {:noreply, put_in(state.change_tokens[key], change_token)}
  end

  @impl true
  def handle_info({:control_state, kind, id, _control_state}, state)
      when kind in [:light, :group] and is_integer(id) do
    notify_change_token(Map.get(state.change_tokens, {:entity, kind, id}))
    {:noreply, state}
  end

  def handle_info({:active_scene_updated, _room_id, _scene_id}, state) do
    state.change_tokens
    |> Enum.filter(fn
      {{:scene, _scene_id}, _token} -> true
      _ -> false
    end)
    |> Enum.each(fn {_key, token} -> notify_change_token(token) end)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp rebuild(state) do
    case AccessoryGraph.build() do
      {:disabled, _topology} ->
        state
        |> stop_hap()
        |> Map.merge(%{topology_hash: nil, change_tokens: %{}})

      {:ok, accessory_server, topology} ->
        hash = AccessoryGraph.topology_hash(topology)

        if hash == state.topology_hash and is_pid(state.hap_pid) do
          state
        else
          state
          |> stop_hap()
          |> start_hap(accessory_server, hash)
        end
    end
  end

  defp start_hap(state, accessory_server, topology_hash) do
    case hap_module().start_link(accessory_server) do
      {:ok, pid} ->
        Logger.info(
          "Started HomeKit bridge with #{length(accessory_server.accessories)} accessories"
        )

        %{state | hap_pid: pid, topology_hash: topology_hash, change_tokens: %{}}

      {:error, {:already_started, pid}} ->
        %{state | hap_pid: pid, topology_hash: topology_hash, change_tokens: %{}}

      {:error, reason} ->
        Logger.warning("Unable to start HomeKit bridge: #{inspect(reason)}")
        %{state | hap_pid: nil, topology_hash: nil, change_tokens: %{}}
    end
  end

  defp stop_hap(%{hap_pid: nil} = state), do: state

  defp stop_hap(%{hap_pid: pid} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      _ = Supervisor.stop(pid, :normal, 5_000)
    end

    %{state | hap_pid: nil}
  catch
    :exit, _reason -> %{state | hap_pid: nil}
  end

  defp notify_change_token(nil), do: :ok

  defp notify_change_token(token) do
    _ = HAP.value_changed(token)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp token_key(opts) do
    case {Keyword.get(opts, :kind), Keyword.get(opts, :id)} do
      {kind, id} when kind in [:light, :group] and is_integer(id) -> {:entity, kind, id}
      {:scene, id} when is_integer(id) -> {:scene, id}
      _ -> {:unknown, opts}
    end
  end

  defp hap_module do
    Application.get_env(:hueworks, :homekit_hap_module, HAP)
  end

  defp maybe_cast(message) do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.cast(pid, message)
      _ -> :ok
    end
  end
end
