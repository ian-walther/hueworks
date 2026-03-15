defmodule Hueworks.DebugLoggingTest do
  use ExUnit.Case, async: false

  alias Hueworks.DebugLogging

  setup do
    previous = Application.get_env(:hueworks, :advanced_debug_logging, false)

    on_exit(fn ->
      Application.put_env(:hueworks, :advanced_debug_logging, previous)
    end)

    :ok
  end

  test "returns false when advanced debug logging is disabled" do
    Application.put_env(:hueworks, :advanced_debug_logging, false)

    refute DebugLogging.enabled?()
  end

  test "returns true when advanced debug logging is enabled" do
    Application.put_env(:hueworks, :advanced_debug_logging, true)

    assert DebugLogging.enabled?()
  end
end
