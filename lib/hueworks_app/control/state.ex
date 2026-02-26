defmodule Hueworks.Control.State do
  @moduledoc """
  Shared in-memory control state backed by ETS.
  """

  use GenServer
  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.Bootstrap.HomeAssistant
  alias Hueworks.Control.Bootstrap.Hue
  alias Hueworks.Control.Bootstrap.Z2M
  alias Hueworks.Control.DesiredState
  alias Hueworks.ActiveScenes
  alias Hueworks.Repo
  alias Hueworks.Schemas.Light
  alias HueworksApp.Cache
  alias Phoenix.PubSub

  @table :hueworks_control_state
  @topic "control_state"
  @light_room_cache_namespace :light_room_ids
  @default_light_room_cache_ttl_ms 60_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}, {:continue, :bootstrap}}
  end

  def get(type, id) do
    case :ets.lookup(@table, {type, id}) do
      [{_key, state}] -> state
      [] -> nil
    end
  end

  def ensure(type, id, defaults) when is_map(defaults) do
    GenServer.call(__MODULE__, {:ensure, type, id, defaults})
  end

  def put(type, id, attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:put, type, id, attrs})
  end

  def bootstrap do
    GenServer.cast(__MODULE__, :bootstrap)
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end

  @impl true
  def handle_call({:ensure, type, id, defaults}, _from, state) do
    key = {type, id}

    case :ets.lookup(@table, key) do
      [{_key, current}] ->
        {:reply, current, state}

      [] ->
        :ets.insert(@table, {key, defaults})
        {:reply, defaults, state}
    end
  end

  @impl true
  def handle_call({:put, type, id, attrs}, _from, state) do
    key = {type, id}

    updated = merge_and_store(key, attrs)
    {:reply, updated, state}
  end

  @impl true
  def handle_cast(:bootstrap, state) do
    do_bootstrap()
    {:noreply, state}
  end

  defp do_bootstrap do
    Task.start(fn ->
      Hue.run()
      HomeAssistant.run()
      Z2M.run()
    end)
  end

  defp merge_and_store(key, attrs) do
    current =
      case :ets.lookup(@table, key) do
        [{_key, existing}] -> existing
        [] -> %{}
      end

    updated = Map.merge(current, attrs)
    maybe_deactivate_scene_on_external_change(key, updated)
    :ets.insert(@table, {key, updated})
    broadcast_update(key, updated)
    updated
  end

  defp broadcast_update({type, id}, state) do
    PubSub.broadcast(Hueworks.PubSub, @topic, {:control_state, type, id, state})
  end

  defp maybe_deactivate_scene_on_external_change({:light, light_id}, updated) do
    desired = DesiredState.get(:light, light_id) || %{}

    if desired != %{} and diverged_from_desired?(desired, updated) do
      case light_room_id(light_id) do
        room_id when is_integer(room_id) ->
          if ActiveScenes.pending_for_room?(room_id) do
            :ok
          else
            _ = ActiveScenes.clear_for_room(room_id)
          end

          :ok

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp maybe_deactivate_scene_on_external_change(_key, _updated), do: :ok

  defp light_room_id(light_id) when is_integer(light_id) do
    Cache.get_or_load(
      @light_room_cache_namespace,
      light_id,
      fn ->
        Repo.one(from(l in Light, where: l.id == ^light_id, select: l.room_id))
      end,
      ttl_ms: light_room_cache_ttl_ms()
    )
  end

  defp light_room_id(_light_id), do: nil

  defp light_room_cache_ttl_ms do
    Application.get_env(
      :hueworks,
      :cache_light_room_ttl_ms,
      @default_light_room_cache_ttl_ms
    )
  end

  defp diverged_from_desired?(desired, updated) do
    Enum.any?(desired, fn {key, desired_value} ->
      updated_value = Map.get(updated, key)
      values_equal?(key, desired_value, updated_value) == false
    end)
  end

  defp values_equal?(_key, desired, updated) when desired == updated, do: true

  defp values_equal?(key, desired, updated) when key in [:brightness, :kelvin] do
    case {Hueworks.Util.to_number(desired), Hueworks.Util.to_number(updated)} do
      {nil, _} -> desired == updated
      {_, nil} -> desired == updated
      {a, b} -> round(a) == round(b)
    end
  end

  defp values_equal?(_key, desired, updated), do: desired == updated
end
