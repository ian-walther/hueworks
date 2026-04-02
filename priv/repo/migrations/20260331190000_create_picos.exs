defmodule Hueworks.Repo.Migrations.CreatePicos do
  use Ecto.Migration

  def change do
    create table(:pico_devices) do
      add(:bridge_id, references(:bridges, on_delete: :delete_all), null: false)
      add(:room_id, references(:rooms, on_delete: :nilify_all))
      add(:source_id, :string, null: false)
      add(:name, :string, null: false)
      add(:display_name, :string)
      add(:hardware_profile, :string, null: false)
      add(:enabled, :boolean, default: true, null: false)
      add(:metadata, :map, default: %{}, null: false)

      timestamps()
    end

    create(unique_index(:pico_devices, [:bridge_id, :source_id]))
    create(index(:pico_devices, [:bridge_id]))
    create(index(:pico_devices, [:room_id]))

    create table(:pico_buttons) do
      add(:pico_device_id, references(:pico_devices, on_delete: :delete_all), null: false)
      add(:source_id, :string, null: false)
      add(:button_number, :integer, null: false)
      add(:slot_index, :integer, null: false)
      add(:action_type, :string)
      add(:action_config, :map, default: %{}, null: false)
      add(:enabled, :boolean, default: true, null: false)
      add(:last_pressed_at, :utc_datetime_usec)
      add(:metadata, :map, default: %{}, null: false)

      timestamps()
    end

    create(unique_index(:pico_buttons, [:pico_device_id, :source_id]))
    create(index(:pico_buttons, [:pico_device_id]))
    create(index(:pico_buttons, [:source_id]))
  end
end
