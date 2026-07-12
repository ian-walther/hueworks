defmodule Hueworks.Repo.Migrations.AddSceneActivationTransitionAndCircadianResumeAt do
  use Ecto.Migration

  def change do
    alter table(:scenes) do
      add :activation_transition_ms, :integer
    end

    alter table(:active_scenes) do
      add :circadian_resume_at, :utc_datetime_usec
    end
  end
end
