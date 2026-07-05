defmodule Hueworks.TestEnvironmentConfigTest do
  use ExUnit.Case, async: true

  test "test database waits briefly for SQLite write locks" do
    assert Application.fetch_env!(:hueworks, Hueworks.Repo)[:busy_timeout] == 10_000
  end

  test "tzdata network autoupdate is disabled in tests" do
    assert Application.fetch_env!(:tzdata, :autoupdate) == :disabled
    refute Process.whereis(Tzdata.ReleaseUpdater)
  end
end
