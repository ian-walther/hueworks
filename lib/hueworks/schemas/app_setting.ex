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
    field(:ha_export_enabled, :boolean, default: false)
    field(:ha_export_scenes_enabled, :boolean, default: false)
    field(:ha_export_room_selects_enabled, :boolean, default: false)
    field(:ha_export_lights_enabled, :boolean, default: false)
    field(:ha_export_mqtt_host, :string)
    field(:ha_export_mqtt_port, :integer, default: 1883)
    field(:ha_export_mqtt_username, :string)
    field(:ha_export_mqtt_password, :string)
    field(:ha_export_discovery_prefix, :string, default: "homeassistant")

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
      :scale_transition_by_brightness,
      :ha_export_enabled,
      :ha_export_scenes_enabled,
      :ha_export_room_selects_enabled,
      :ha_export_lights_enabled,
      :ha_export_mqtt_host,
      :ha_export_mqtt_port,
      :ha_export_mqtt_username,
      :ha_export_mqtt_password,
      :ha_export_discovery_prefix
    ])
    |> validate_required([:scope])
    |> validate_inclusion(:scope, ["global"])
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_number(:default_transition_ms, greater_than_or_equal_to: 0)
    |> validate_number(:ha_export_mqtt_port,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 65_535
    )
    |> validate_length(:ha_export_mqtt_host, max: 255)
    |> validate_length(:ha_export_mqtt_username, max: 255)
    |> validate_length(:ha_export_mqtt_password, max: 255)
    |> validate_length(:ha_export_discovery_prefix, min: 1, max: 255)
    |> validate_ha_export_requirements()
    |> unique_constraint(:scope)
  end

  def global_changeset(app_setting, attrs) do
    app_setting
    |> changeset(attrs)
    |> validate_required([:latitude, :longitude, :timezone])
    |> validate_length(:timezone, min: 1, max: 128)
  end

  defp validate_ha_export_requirements(changeset) do
    if ha_export_enabled?(changeset) do
      changeset
      |> validate_required([:ha_export_mqtt_host])
      |> validate_required([:ha_export_discovery_prefix])
    else
      changeset
    end
  end

  defp ha_export_enabled?(changeset) do
    get_field(changeset, :ha_export_scenes_enabled) == true or
      get_field(changeset, :ha_export_room_selects_enabled) == true or
      get_field(changeset, :ha_export_lights_enabled) == true or
      get_field(changeset, :ha_export_enabled) == true
  end
end
