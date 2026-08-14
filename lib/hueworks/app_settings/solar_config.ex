defmodule Hueworks.AppSettings.SolarConfig do
  @moduledoc """
  Boundary module for solar/transition app settings.

  Owns parsing and normalization for: latitude, longitude, timezone,
  default_transition_ms, and scale_transition_by_brightness.

  Does not validate ranges — that is AppSetting.global_changeset's job.
  Does not change the persisted shape — these remain flat columns on AppSetting.
  """

  alias Hueworks.AppSettings.FieldParser
  alias Hueworks.Util

  @default_transition_ms 500
  @default_scale_transition_by_brightness true

  def default_transition_ms, do: @default_transition_ms

  def default_scale_transition_by_brightness?,
    do: @default_scale_transition_by_brightness

  @doc """
  Normalizes a mixed-key attrs map to an atom-keyed map suitable for
  AppSetting.global_changeset. Missing fields are omitted, explicitly blank
  fields are preserved as nil, and invalid present fields return errors.
  """
  def normalize(attrs) when is_map(attrs) do
    parse_attrs(attrs)
  end

  def normalize(_), do: {:error, [{"solar_config", "must be a map"}]}

  @doc """
  Builds a fallback attrs map from Application config (no DB row present).
  """
  def fallback_attrs do
    config = Application.get_env(:hueworks, :global_solar_config, %{})

    %{
      latitude: Util.to_number(config[:latitude] || config["latitude"]),
      longitude: Util.to_number(config[:longitude] || config["longitude"]),
      timezone: fallback_value(FieldParser.parse_string(config[:timezone] || config["timezone"])),
      default_transition_ms:
        Application.get_env(:hueworks, :default_transition_ms, default_transition_ms()),
      scale_transition_by_brightness:
        Util.parse_optional_bool(
          Application.get_env(
            :hueworks,
            :scale_transition_by_brightness,
            default_scale_transition_by_brightness?()
          )
        ) == true
    }
  end

  defp parse_attrs(attrs) do
    {attrs, errors} =
      {%{}, []}
      |> FieldParser.parse_present_field(
        :latitude,
        FieldParser.get_field_value(attrs, :latitude, "latitude"),
        &FieldParser.parse_number/1
      )
      |> FieldParser.parse_present_field(
        :longitude,
        FieldParser.get_field_value(attrs, :longitude, "longitude"),
        &FieldParser.parse_number/1
      )
      |> FieldParser.parse_present_field(
        :timezone,
        FieldParser.get_field_value(attrs, :timezone, "timezone"),
        &FieldParser.parse_string/1
      )
      |> FieldParser.parse_present_field(
        :default_transition_ms,
        FieldParser.get_field_value(attrs, :default_transition_ms, "default_transition_ms"),
        &FieldParser.parse_non_negative_integer/1
      )
      |> FieldParser.parse_present_field(
        :scale_transition_by_brightness,
        FieldParser.get_field_value(
          attrs,
          :scale_transition_by_brightness,
          "scale_transition_by_brightness"
        ),
        &FieldParser.parse_bool/1
      )

    case errors do
      [] -> {:ok, attrs}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp fallback_value({:ok, value}), do: value
end
