defmodule Hueworks.Repo.Migrations.AddOnboardingStateToAppSettings do
  use Ecto.Migration

  def change do
    alter table(:app_settings) do
      add(:onboarding_path, :string)
      add(:onboarding_completed_at, :utc_datetime_usec)
      add(:onboarding_dismissed_at, :utc_datetime_usec)
    end
  end
end
