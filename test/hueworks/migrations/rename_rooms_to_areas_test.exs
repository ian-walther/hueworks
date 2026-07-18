defmodule Hueworks.Migrations.RenameRoomsToAreasTest do
  use ExUnit.Case, async: true

  alias Hueworks.Repo.Migrations.RenameRoomsToAreas

  unless Code.ensure_loaded?(RenameRoomsToAreas) do
    Code.require_file(
      Path.expand(
        "../../../priv/repo/migrations/20260717140000_rename_rooms_to_areas.exs",
        __DIR__
      )
    )
  end

  test "renames the Pico action config ownership key without changing other data" do
    config = %{
      "target_kind" => "control_groups",
      "target_ids" => ["all"],
      "light_ids" => [1, 2],
      "room_id" => 12,
      "future_field" => %{"nested" => true}
    }

    assert %{
             "target_kind" => "control_groups",
             "target_ids" => ["all"],
             "light_ids" => [1, 2],
             "area_id" => 12,
             "future_field" => %{"nested" => true}
           } = RenameRoomsToAreas.rename_action_config_key(config, "room_id", "area_id")
  end

  test "does not overwrite an already populated destination key" do
    config = %{"room_id" => 12, "area_id" => 24}

    assert %{"area_id" => 24} =
             RenameRoomsToAreas.rename_action_config_key(config, "room_id", "area_id")
  end

  test "leaves unrelated Pico action configs unchanged" do
    config = %{"target_kind" => "scene", "target_id" => 42}

    assert RenameRoomsToAreas.rename_action_config_key(config, "room_id", "area_id") == config
  end

  test "renames legacy Pico Area ownership metadata without changing source metadata" do
    metadata = %{
      "area_id" => "2",
      "room_override" => true,
      "detected_room_id" => 4,
      "control_groups" => [%{"id" => "group-1", "light_ids" => [12]}]
    }

    assert %{
             "area_id" => "2",
             "area_override" => true,
             "detected_area_id" => 4,
             "control_groups" => [%{"id" => "group-1", "light_ids" => [12]}]
           } = RenameRoomsToAreas.rename_pico_metadata(metadata)
  end

  test "preserves populated Area metadata while removing legacy Room keys" do
    metadata = %{
      "room_override" => false,
      "area_override" => true,
      "detected_room_id" => 4,
      "detected_area_id" => 8
    }

    assert %{"area_override" => true, "detected_area_id" => 8} =
             RenameRoomsToAreas.rename_pico_metadata(metadata)
  end
end
