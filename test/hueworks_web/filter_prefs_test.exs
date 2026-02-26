defmodule HueworksWeb.FilterPrefsTest do
  use ExUnit.Case, async: false

  alias HueworksWeb.FilterPrefs

  setup do
    :ok = HueworksApp.Cache.flush_namespace(:filter_prefs)
    :ok
  end

  test "get/1 returns empty map for nil session id" do
    assert FilterPrefs.get(nil) == %{}
  end

  test "get/1 returns empty map for unknown session id" do
    assert FilterPrefs.get("missing") == %{}
  end

  test "update/2 stores and merges prefs by session id" do
    assert FilterPrefs.update("sess-1", %{group_filter: "all"}) == %{group_filter: "all"}

    assert FilterPrefs.update("sess-1", %{light_filter: "living"}) == %{
             group_filter: "all",
             light_filter: "living"
           }

    assert FilterPrefs.get("sess-1") == %{
             group_filter: "all",
             light_filter: "living"
           }
  end

  test "update/2 with nil session id returns updates and does not persist" do
    updates = %{group_filter: "bedroom"}

    assert FilterPrefs.update(nil, updates) == updates
    assert FilterPrefs.get(nil) == %{}
    assert FilterPrefs.get("sess-2") == %{}
  end
end
