defmodule HueworksWeb.FilterPrefs do
  @moduledoc false

  alias HueworksApp.Cache

  @cache_namespace :filter_prefs

  def get(nil), do: %{}

  def get(session_id) do
    Cache.get(@cache_namespace, session_id, %{})
  end

  def update(nil, updates), do: updates

  def update(session_id, updates) when is_map(updates) do
    prefs = Map.merge(get(session_id), updates)
    :ok = Cache.put(@cache_namespace, session_id, prefs)
    prefs
  end
end
