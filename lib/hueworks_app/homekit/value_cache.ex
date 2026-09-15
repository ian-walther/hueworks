defmodule Hueworks.HomeKit.ValueCache do
  @moduledoc """
  Last value HomeKit wrote for each characteristic.

  Reads prefer a cached value until the bridge reports a matching value or the entry
  expires, so the Home app does not snap back to stale state between a write and the
  bridge confirming it. Each write gets a generation so a failed apply can drop only the
  entry it owns, never a newer write of the same value. Every write and clear is broadcast
  on `topic/0` so the bridge can re-notify subscribed controllers.
  """

  use GenServer

  alias Hueworks.HomeKit.ValueStore
  alias Phoenix.PubSub

  @table :hueworks_homekit_values
  @topic "homekit_values"
  @default_ttl_ms 5_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def topic, do: @topic

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  @doc "Caches a written value and returns the generation that owns the entry."
  def put(kind, id, characteristic, value) do
    generation = System.unique_integer([:positive, :monotonic])
    :ets.insert(@table, {{kind, id, characteristic}, value, now_ms(), generation})
    broadcast({:homekit_value_written, kind, id, characteristic, value, ttl_ms()})
    generation
  end

  def get(kind, id, characteristic) do
    key = {kind, id, characteristic}

    case :ets.lookup(@table, key) do
      [{^key, value, written_at_ms, _generation}] ->
        if now_ms() - written_at_ms <= ttl_ms() do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc "Drops cached entries that the observed state now agrees with."
  def reconcile(kind, id, observed_state) when is_map(observed_state) do
    @table
    |> :ets.match_object({{kind, id, :_}, :_, :_, :_})
    |> Enum.each(fn {{_kind, _id, characteristic} = key, value, _written_at_ms, _generation} ->
      if ValueStore.observed_matches?(characteristic, observed_state, value) do
        :ets.delete(@table, key)
      end
    end)

    :ok
  end

  @doc """
  Drops the cached entries owned by `generations` (a map of characteristic to generation)
  once the write that produced them has finished or failed. Entries written since, even
  with the same value, are left alone.
  """
  def invalidate(kind, id, generations) when is_map(generations) do
    Enum.each(generations, fn {characteristic, generation} ->
      :ets.match_delete(@table, {{kind, id, characteristic}, :_, :_, generation})
    end)

    broadcast({:homekit_value_cleared, kind, id})
  end

  @doc """
  Drops entries for `characteristics` that were written before `generation`. Used when a
  write in one color mode supersedes earlier writes in the other: a newer accepted write
  is never touched, whether it is pending, in flight, or already applied.
  """
  def invalidate_older(kind, id, characteristics, generation) when is_list(characteristics) do
    Enum.each(characteristics, fn characteristic ->
      :ets.select_delete(@table, [
        {{{kind, id, characteristic}, :_, :_, :"$1"}, [{:<, :"$1", generation}], [true]}
      ])
    end)

    broadcast({:homekit_value_cleared, kind, id})
  end

  def clear(kind, id) do
    :ets.match_delete(@table, {{kind, id, :_}, :_, :_, :_})
    broadcast({:homekit_value_cleared, kind, id})
  end

  def clear_kind(kind) do
    :ets.match_delete(@table, {{kind, :_, :_}, :_, :_, :_})
    broadcast({:homekit_value_cleared, kind, nil})
  end

  defp broadcast(message) do
    PubSub.broadcast(Hueworks.PubSub, @topic, message)
    :ok
  end

  defp ttl_ms, do: Application.get_env(:hueworks, :homekit_value_cache_ttl_ms, @default_ttl_ms)

  defp now_ms, do: System.monotonic_time(:millisecond)
end
