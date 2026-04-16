Code.require_file("support/logger_filters.exs", __DIR__)

_ =
  :logger.add_primary_filter(
    :hueworks_suppress_exqlite_client_exits,
    {&Hueworks.TestLogFilter.suppress_exqlite_client_exits/2, nil}
  )

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Hueworks.Repo, :manual)
