defmodule Hueworks.Repo.Migrations.AddBridgeImportReviewBlob do
  use Ecto.Migration

  def change do
    alter table(:bridge_imports) do
      add(:review_blob, :map)
    end
  end
end
