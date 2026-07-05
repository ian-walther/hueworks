defmodule Hueworks.Repo.Migrations.BackfillLightGroupDisplayNames do
  use Ecto.Migration

  def up do
    execute(
      "UPDATE lights SET display_name = name WHERE display_name IS NULL OR display_name = ''"
    )

    execute(
      "UPDATE groups SET display_name = name WHERE display_name IS NULL OR display_name = ''"
    )
  end

  def down, do: :ok
end
