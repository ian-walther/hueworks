defmodule Hueworks.Schemas.AppSetting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_settings" do
    field(:scope, :string, default: "global")
    field(:latitude, :float)
    field(:longitude, :float)
    field(:timezone, :string)
    field(:default_transition_ms, :integer, default: 0)
    field(:scale_transition_by_brightness, :boolean, default: false)

    timestamps()
  end

  def changeset(app_setting, attrs) do
    app_setting
    |> cast(attrs, [
      :scope,
      :latitude,
      :longitude,
      :timezone,
      :default_transition_ms,
      :scale_transition_by_brightness
    ])
    |> validate_required([:scope])
    |> validate_inclusion(:scope, ["global"])
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_number(:default_transition_ms, greater_than_or_equal_to: 0)
    |> unique_constraint(:scope)
  end

  def global_changeset(app_setting, attrs) do
    app_setting
    |> changeset(attrs)
    |> validate_required([:latitude, :longitude, :timezone])
    |> validate_length(:timezone, min: 1, max: 128)
  end
end
