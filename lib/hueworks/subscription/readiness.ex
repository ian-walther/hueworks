defmodule Hueworks.Subscription.Readiness do
  @moduledoc false

  alias Hueworks.Repo

  def bridges_table_ready? do
    case Ecto.Adapters.SQL.query(
           Repo,
           "SELECT name FROM sqlite_master WHERE type='table' AND name='bridges' LIMIT 1",
           []
         ) do
      {:ok, %{num_rows: 1}} -> true
      {:ok, _result} -> false
      {:error, _reason} -> false
    end
  rescue
    _error -> false
  end
end
