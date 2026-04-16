defmodule Hueworks.Repo.Migrations.BackfillLegacyPicoButtonActionConfigs do
  use Ecto.Migration

  alias Hueworks.Picos.LegacyActionConfigBackfill

  def up do
    execute(fn -> LegacyActionConfigBackfill.run(repo()) end)
  end

  def down, do: :ok
end
