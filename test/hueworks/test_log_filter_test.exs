defmodule Hueworks.TestLogFilterTest do
  use ExUnit.Case, async: true

  alias Hueworks.TestLogFilter

  test "suppresses the specific exqlite client-exit disconnect noise" do
    event = %{
      level: :error,
      msg:
        {:string,
         "Elixir.Exqlite.Connection (#PID<0.123.0> (\"db_conn_1\")) disconnected: ** (DBConnection.ConnectionError) client #PID<0.456.0> exited"}
    }

    assert :stop = TestLogFilter.suppress_exqlite_client_exits(event, nil)
  end

  test "passes through unrelated errors" do
    event = %{level: :error, msg: {:string, "something else failed"}}

    assert ^event = TestLogFilter.suppress_exqlite_client_exits(event, nil)
  end
end
