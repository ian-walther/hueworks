defmodule HueworksWeb.FilterPrefs do
  @moduledoc false

  use GenServer

  @table :hueworks_filter_prefs

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get(nil), do: %{}

  def get(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, prefs}] -> prefs
      _ -> %{}
    end
  end

  def update(nil, updates), do: updates

  def update(session_id, updates) when is_map(updates) do
    prefs = Map.merge(get(session_id), updates)
    :ets.insert(@table, {session_id, prefs})
    prefs
  end

  @impl true
  def init(_state) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end
end
