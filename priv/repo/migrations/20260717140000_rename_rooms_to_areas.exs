defmodule Hueworks.Repo.Migrations.RenameRoomsToAreas do
  use Ecto.Migration

  @area_tables [:lights, :groups, :scenes, :active_scenes, :pico_devices, :presence_inputs]

  def up do
    rename(table(:rooms), to: table(:areas))

    Enum.each(@area_tables, fn table_name ->
      rename(table(table_name), :room_id, to: :area_id)
    end)

    rename(
      table(:app_settings),
      :ha_export_room_selects_enabled,
      to: :ha_export_area_selects_enabled
    )

    flush()
    rewrite_pico_action_configs(repo(), "room_id", "area_id")
    rewrite_pico_metadata(repo())

    drop_legacy_indexes()
    create_identity_presence_triggers()

    create(unique_index(:areas, [:ha_device_identifier]))
    create(unique_index(:areas, [:ha_scene_select_identifier]))
    create(index(:lights, [:area_id]))
    create(index(:groups, [:area_id]))
    create(index(:scenes, [:area_id]))
    create(unique_index(:active_scenes, [:area_id]))
    create(index(:pico_devices, [:area_id]))
    create(index(:presence_inputs, [:area_id]))
  end

  def down do
    raise "Room-to-Area rollback requires restoring the verified pre-migration database snapshot"
  end

  def rewrite_pico_action_configs(repo, source_key, destination_key) do
    repo.query!("SELECT id, action_config FROM pico_buttons", []).rows
    |> Enum.each(fn [id, encoded_config] ->
      config = Jason.decode!(encoded_config)
      renamed = rename_action_config_key(config, source_key, destination_key)

      if renamed != config do
        repo.query!(
          "UPDATE pico_buttons SET action_config = ? WHERE id = ?",
          [Jason.encode!(renamed), id]
        )
      end
    end)

    :ok
  end

  def rename_action_config_key(config, source_key, destination_key)
      when is_map(config) and is_binary(source_key) and is_binary(destination_key) do
    case Map.fetch(config, source_key) do
      {:ok, value} ->
        config
        |> Map.put_new(destination_key, value)
        |> Map.delete(source_key)

      :error ->
        config
    end
  end

  def rewrite_pico_metadata(repo) do
    repo.query!("SELECT id, metadata FROM pico_devices", []).rows
    |> Enum.each(fn [id, encoded_metadata] ->
      metadata = Jason.decode!(encoded_metadata)
      renamed = rename_pico_metadata(metadata)

      if renamed != metadata do
        repo.query!("UPDATE pico_devices SET metadata = ? WHERE id = ?", [
          Jason.encode!(renamed),
          id
        ])
      end
    end)

    :ok
  end

  def rename_pico_metadata(metadata) when is_map(metadata) do
    metadata
    |> rename_action_config_key("room_override", "area_override")
    |> rename_action_config_key("detected_room_id", "detected_area_id")
  end

  defp drop_legacy_indexes do
    execute("DROP INDEX IF EXISTS rooms_ha_device_identifier_index")
    execute("DROP INDEX IF EXISTS rooms_ha_scene_select_identifier_index")
    execute("DROP INDEX IF EXISTS lights_room_id_index")
    execute("DROP INDEX IF EXISTS groups_room_id_index")
    execute("DROP INDEX IF EXISTS scenes_room_id_index")
    execute("DROP INDEX IF EXISTS active_scenes_room_id_index")
    execute("DROP INDEX IF EXISTS pico_devices_room_id_index")
    execute("DROP INDEX IF EXISTS presence_inputs_room_id_index")
  end

  defp create_identity_presence_triggers do
    execute("""
    CREATE TRIGGER areas_published_identity_required_on_insert
    BEFORE INSERT ON areas
    WHEN NEW.ha_device_identifier IS NULL
      OR NEW.ha_device_identifier = ''
      OR NEW.ha_scene_select_identifier IS NULL
      OR NEW.ha_scene_select_identifier = ''
    BEGIN
      SELECT RAISE(ABORT, 'areas require persisted published identities');
    END
    """)

    execute("""
    CREATE TRIGGER areas_published_identity_required_on_update
    BEFORE UPDATE OF ha_device_identifier, ha_scene_select_identifier ON areas
    WHEN NEW.ha_device_identifier IS NULL
      OR NEW.ha_device_identifier = ''
      OR NEW.ha_scene_select_identifier IS NULL
      OR NEW.ha_scene_select_identifier = ''
    BEGIN
      SELECT RAISE(ABORT, 'areas require persisted published identities');
    END
    """)
  end
end
