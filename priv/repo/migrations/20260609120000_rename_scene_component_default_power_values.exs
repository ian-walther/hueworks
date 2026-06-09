defmodule Hueworks.Repo.Migrations.RenameSceneComponentDefaultPowerValues do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE scene_component_lights
    SET default_power = CASE default_power
      WHEN 'force_on' THEN 'default_on'
      WHEN 'force_off' THEN 'default_off'
      ELSE default_power
    END
    """)
  end

  def down do
    execute("""
    UPDATE scene_component_lights
    SET default_power = CASE default_power
      WHEN 'default_on' THEN 'force_on'
      WHEN 'default_off' THEN 'force_off'
      ELSE default_power
    END
    """)
  end
end
