defmodule HueworksApp.Cache.Store do
  @moduledoc """
  Lightweight ETS-backed cache with optional TTL per entry.
  """

  use GenServer

  @table :hueworks_app_cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  def table, do: @table

  def put(namespace, key, value, opts \\ []) do
    if :ets.whereis(@table) == :undefined do
      :ok
    else
      ttl_ms = Keyword.get(opts, :ttl_ms)

      expires_at =
        if is_integer(ttl_ms) and ttl_ms > 0 do
          now_ms() + ttl_ms
        else
          nil
        end

      :ets.insert(@table, {{namespace, key}, value, expires_at})
      :ok
    end
  end

  def get(namespace, key) do
    if :ets.whereis(@table) == :undefined do
      :miss
    else
      case :ets.lookup(@table, {namespace, key}) do
        [{{^namespace, ^key}, value, expires_at}] ->
          if expired?(expires_at) do
            :ets.delete(@table, {namespace, key})
            :miss
          else
            {:hit, value}
          end

        _ ->
          :miss
      end
    end
  end

  def delete(namespace, key) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, {namespace, key})
    end

    :ok
  end

  def flush_namespace(namespace) do
    if :ets.whereis(@table) != :undefined do
      :ets.match_delete(@table, {{namespace, :_}, :_, :_})
    end

    :ok
  end

  def flush_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  defp expired?(nil), do: false
  defp expired?(expires_at), do: now_ms() >= expires_at

  defp now_ms, do: System.monotonic_time(:millisecond)
end
