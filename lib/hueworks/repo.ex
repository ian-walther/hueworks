defmodule Hueworks.Repo do
  use Ecto.Repo,
    otp_app: :hueworks,
    adapter: Ecto.Adapters.SQLite3
end
