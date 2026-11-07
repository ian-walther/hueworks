defmodule Hueworks.Repo.Migrations.AddGlobalSolarTiming do
  use Ecto.Migration

  @object_config "CASE WHEN json_valid(config) THEN json_type(config) END = 'object'"

  # Existing circadian profiles keep their local timing. New profiles inherit
  # the house-wide timing because they are created with explicit false flags.
  def up do
    alter table(:app_settings) do
      add(:min_sunrise_time, :string)
      add(:max_sunrise_time, :string)
      add(:min_sunset_time, :string)
      add(:max_sunset_time, :string)
    end

    execute("""
    UPDATE light_states
    SET config = json_insert(
      config,
      '$.override_sunrise_timing', json('true'),
      '$.override_sunset_timing', json('true')
    )
    WHERE type = 'circadian' AND #{@object_config}
    """)
  end

  def down do
    execute("""
    UPDATE light_states
    SET config = json_remove(
      config,
      '$.override_sunrise_timing',
      '$.override_sunset_timing'
    )
    WHERE type = 'circadian' AND #{@object_config}
    """)

    alter table(:app_settings) do
      remove(:min_sunrise_time)
      remove(:max_sunrise_time)
      remove(:min_sunset_time)
      remove(:max_sunset_time)
    end
  end
end
