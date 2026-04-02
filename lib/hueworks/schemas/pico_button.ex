defmodule Hueworks.Schemas.PicoButton do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pico_buttons" do
    field(:source_id, :string)
    field(:button_number, :integer)
    field(:slot_index, :integer)
    field(:action_type, :string)
    field(:action_config, :map, default: %{})
    field(:enabled, :boolean, default: true)
    field(:last_pressed_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    belongs_to(:pico_device, Hueworks.Schemas.PicoDevice)

    timestamps()
  end

  def changeset(button, attrs) do
    button
    |> cast(attrs, [
      :pico_device_id,
      :source_id,
      :button_number,
      :slot_index,
      :action_type,
      :action_config,
      :enabled,
      :last_pressed_at,
      :metadata
    ])
    |> validate_required([:pico_device_id, :source_id, :button_number, :slot_index])
    |> unique_constraint([:pico_device_id, :source_id])
  end
end
