defmodule Hueworks.Repo.Migrations.BackfillLegacyPicoButtonActionConfigs do
  use Ecto.Migration

  @scene_sql """
  UPDATE pico_buttons
  SET action_config = json_remove(
    json_set(action_config, '$.scene_id', json_extract(action_config, '$.target_id')),
    '$.target_id'
  )
  WHERE json_extract(action_config, '$.target_kind') = 'scene'
    AND json_type(action_config, '$.target_id') IS NOT NULL
    AND json_type(action_config, '$.scene_id') IS NULL
  """

  def up do
    execute(@scene_sql)
  end

  def down, do: :ok
end
