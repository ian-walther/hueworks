defmodule Hueworks.Schemas.PicoButton do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Schemas.PicoButton.ActionConfig

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
    |> validate_action_config()
    |> unique_constraint([:pico_device_id, :source_id])
  end

  def action_config_struct(%__MODULE__{action_config: action_config}),
    do: action_config_struct(action_config)

  def action_config_struct(action_config), do: ActionConfig.load(action_config)

  defp validate_action_config(changeset) do
    config = get_field(changeset, :action_config) || %{}

    case ActionConfig.normalize(config) do
      {:ok, normalized} ->
        put_change(changeset, :action_config, normalized)

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {key, message}, acc ->
          add_error(acc, :action_config, "#{key} #{message}")
        end)
    end
  end
end
