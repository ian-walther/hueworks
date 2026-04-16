defmodule Hueworks.Schemas.PicoButton do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Schemas.PicoButton.ActionConfig

  schema "pico_buttons" do
    field(:source_id, :string)
    field(:button_number, :integer)
    field(:slot_index, :integer)
    field(:action_type, :string)
    embeds_one(:action_config, ActionConfig,
      source: :action_config,
      on_replace: :update,
      defaults_to_struct: true
    )
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
      :enabled,
      :last_pressed_at,
      :metadata
    ])
    |> validate_required([:pico_device_id, :source_id, :button_number, :slot_index])
    |> cast_embed(:action_config, with: &ActionConfig.changeset/2)
    |> unique_constraint([:pico_device_id, :source_id])
  end

  def action_config_struct(%__MODULE__{action_config: %ActionConfig{} = action_config}),
    do: action_config

  def action_config_struct(%__MODULE__{action_config: action_config}), do: action_config_struct(action_config)
  def action_config_struct(%ActionConfig{} = action_config), do: action_config
  def action_config_struct(action_config), do: ActionConfig.load(action_config)
end
