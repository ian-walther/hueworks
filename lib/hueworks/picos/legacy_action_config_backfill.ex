defmodule Hueworks.Picos.LegacyActionConfigBackfill do
  @moduledoc false

  alias Ecto.Adapters.SQL

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

  @control_group_sql """
  UPDATE pico_buttons
  SET action_config = json_remove(
    json_set(action_config, '$.control_group_id', json_extract(action_config, '$.target_id')),
    '$.target_id'
  )
  WHERE json_extract(action_config, '$.target_kind') = 'control_group'
    AND json_type(action_config, '$.target_id') IS NOT NULL
    AND json_type(action_config, '$.control_group_id') IS NULL
  """

  def run(repo) do
    repo
    |> SQL.query!(@scene_sql, [])
    |> then(fn _ -> SQL.query!(repo, @control_group_sql, []) end)

    :ok
  end
end
