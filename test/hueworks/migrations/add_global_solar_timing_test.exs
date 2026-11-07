defmodule Hueworks.Migrations.AddGlobalSolarTimingTest do
  use ExUnit.Case, async: false

  alias Hueworks.Circadian
  alias Hueworks.Schemas.LightState

  # A separate repo over a private file, so no shared database is touched.
  defmodule UpgradeRepo do
    use Ecto.Repo, otp_app: :hueworks, adapter: Ecto.Adapters.SQLite3
  end

  @previous_version 20_260_913_120_000
  @migration_version 20_261_106_120_000
  @timestamp "2026-09-13 12:00:00"

  @local_config %{
    "min_brightness" => 10,
    "max_brightness" => 90,
    "min_color_temp" => 2000,
    "max_color_temp" => 4000,
    "temperature_ceiling_kelvin" => 3800,
    "brightness_mode" => "linear",
    "brightness_mode_time_dark" => 1800,
    "brightness_mode_time_light" => 7200,
    "sunrise_time" => "06:15:00",
    "min_sunset_time" => "17:00:00",
    "max_sunset_time" => "20:00:00",
    "sunset_offset" => -900,
    "brightness_sunset_offset" => 300,
    "temperature_sunrise_offset" => -600
  }

  @solar_config %{latitude: 47.6062, longitude: -122.3321, timezone: "America/Los_Angeles"}

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "hueworks_upgrade_#{System.unique_integer([:positive])}.db"
      )

    start_supervised!({UpgradeRepo, database: path, pool_size: 1, log: false})

    conflict_option = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    on_exit(fn ->
      Code.put_compiler_option(:ignore_module_conflict, conflict_option)
      Enum.each(["", "-shm", "-wal"], &File.rm(path <> &1))
    end)

    migrate(:up, @previous_version)

    :ok
  end

  test "backfills explicit local timing on circadian profiles only" do
    shaped = insert_light_state("Default Circadian", "circadian", Jason.encode!(@local_config))
    empty = insert_light_state("Empty Circadian", "circadian", "{}")

    manual_config =
      Jason.encode!(%{"mode" => "temperature", "brightness" => 40, "temperature" => 3000})

    manual = insert_light_state("Soft", "manual", manual_config)
    malformed = insert_light_state("Broken", "circadian", "not json")
    identity_before = light_state_identity()

    migrate(:up, @migration_version)

    assert stored_config(shaped) ==
             Map.merge(@local_config, %{
               "override_sunrise_timing" => true,
               "override_sunset_timing" => true
             })

    assert stored_config(empty) == %{
             "override_sunrise_timing" => true,
             "override_sunset_timing" => true
           }

    assert raw_config(manual) == manual_config
    assert raw_config(malformed) == "not json"
    assert light_state_identity() == identity_before
  end

  test "does not replace a flag that is already stored" do
    config = Jason.encode!(%{"override_sunset_timing" => false, "min_brightness" => 12})
    id = insert_light_state("Early Adopter", "circadian", config)

    migrate(:up, @migration_version)

    assert stored_config(id) == %{
             "min_brightness" => 12,
             "override_sunrise_timing" => true,
             "override_sunset_timing" => false
           }
  end

  test "adds blank global bounds and preserves every other setting" do
    UpgradeRepo.query!(
      """
      INSERT INTO app_settings
        (scope, latitude, longitude, timezone, default_transition_ms,
         ha_export_mqtt_host, ha_export_mqtt_password, api_token, inserted_at, updated_at)
      VALUES
        ('global', 47.6062, -122.3321, 'America/Los_Angeles', 750,
         'mqtt.local', 'secret', 'token', ?, ?)
      """,
      [@timestamp, @timestamp]
    )

    before_row = app_settings_row()

    migrate(:up, @migration_version)

    after_row = app_settings_row()

    assert Map.take(after_row, Map.keys(before_row)) == before_row

    assert Map.drop(after_row, Map.keys(before_row)) == %{
             "min_sunrise_time" => nil,
             "max_sunrise_time" => nil,
             "min_sunset_time" => nil,
             "max_sunset_time" => nil
           }
  end

  test "leaves scene assignments and active scenes untouched" do
    state_id = insert_light_state("Default Circadian", "circadian", Jason.encode!(@local_config))

    UpgradeRepo.query!(
      """
      INSERT INTO areas
        (id, name, ha_device_identifier, ha_scene_select_identifier, inserted_at, updated_at)
      VALUES (1, 'Main Floor', 'device', 'select', ?, ?)
      """,
      [@timestamp, @timestamp]
    )

    UpgradeRepo.query!(
      """
      INSERT INTO scenes (id, name, area_id, inserted_at, updated_at)
      VALUES (1, 'Evening Auto', 1, ?, ?)
      """,
      [@timestamp, @timestamp]
    )

    UpgradeRepo.query!(
      """
      INSERT INTO scene_components (id, name, scene_id, light_state_id, inserted_at, updated_at)
      VALUES (1, 'Everything', 1, ?, ?, ?)
      """,
      [state_id, @timestamp, @timestamp]
    )

    UpgradeRepo.query!(
      """
      INSERT INTO active_scenes (area_id, scene_id, power_overrides, inserted_at, updated_at)
      VALUES (1, 1, ?, ?, ?)
      """,
      [Jason.encode!(%{"12" => "off"}), @timestamp, @timestamp]
    )

    rows_before = scene_table_rows()

    migrate(:up, @migration_version)

    assert scene_table_rows() == rows_before
  end

  test "preserves circadian outputs through the upgrade, even with global bounds" do
    id = insert_light_state("Default Circadian", "circadian", Jason.encode!(@local_config))
    outputs_before = outputs(circadian_config(id), @solar_config)

    migrate(:up, @migration_version)

    bounds = %{min_sunset_time: "22:00", max_sunrise_time: "04:00"}

    assert outputs(circadian_config(id), @solar_config) == outputs_before
    assert outputs(circadian_config(id), Map.merge(@solar_config, bounds)) == outputs_before
  end

  test "rolls back to the previous representation" do
    id = insert_light_state("Default Circadian", "circadian", Jason.encode!(@local_config))

    migrate(:up, @migration_version)
    migrate(:down, @migration_version)

    assert stored_config(id) == @local_config
    refute "min_sunset_time" in UpgradeRepo.query!("SELECT * FROM app_settings").columns

    migrate(:up, @migration_version)
    assert stored_config(id)["override_sunset_timing"] == true
  end

  defp migrate(direction, version) do
    Ecto.Migrator.run(
      UpgradeRepo,
      Application.app_dir(:hueworks, "priv/repo/migrations"),
      direction,
      to: version,
      log: false,
      log_migrations_sql: false
    )
  end

  defp insert_light_state(name, type, config) do
    %{rows: [[id]]} =
      UpgradeRepo.query!(
        """
        INSERT INTO light_states (name, type, config, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        RETURNING id
        """,
        [name, type, config, @timestamp, @timestamp]
      )

    id
  end

  defp raw_config(id) do
    %{rows: [[config]]} = UpgradeRepo.query!("SELECT config FROM light_states WHERE id = ?", [id])
    config
  end

  defp stored_config(id), do: id |> raw_config() |> Jason.decode!()

  defp light_state_identity do
    UpgradeRepo.query!("SELECT id, name, type, inserted_at, updated_at FROM light_states").rows
  end

  defp scene_table_rows do
    Map.new(
      ["areas", "scenes", "scene_components", "active_scenes"],
      &{&1, UpgradeRepo.query!("SELECT * FROM #{&1}").rows}
    )
  end

  defp app_settings_row do
    %{columns: columns, rows: [row]} = UpgradeRepo.query!("SELECT * FROM app_settings")

    columns
    |> Enum.zip(row)
    |> Map.new()
  end

  defp circadian_config(id) do
    LightState
    |> UpgradeRepo.get!(id)
    |> LightState.circadian_config()
  end

  defp outputs(config, solar_config) do
    for date <- [~D[2026-12-21], ~D[2026-06-21]], hour <- 0..23 do
      now = DateTime.new!(date, Time.new!(hour, 30, 0), "America/Los_Angeles")
      {:ok, result} = Circadian.calculate(config, solar_config, now)
      {result.brightness, result.kelvin}
    end
  end
end
