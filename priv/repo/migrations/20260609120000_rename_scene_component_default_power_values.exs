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

    alter table(:scene_component_lights) do
      modify(:default_power, :string, null: false, default: "default_on")
    end
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

    alter table(:scene_component_lights) do
      modify(:default_power, :string, null: false, default: "force_on")
    end
  end
end
