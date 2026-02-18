defmodule Hueworks.AppSettings do
  @moduledoc """
  Global app settings storage with DB persistence and app-config fallback.
  """

  alias Hueworks.Repo
  alias Hueworks.Schemas.AppSetting

  @global_scope "global"
  @config_key :global_solar_config

  def get_global do
    case Repo.get_by(AppSetting, scope: @global_scope) do
      %AppSetting{} = app_setting ->
        app_setting

      nil ->
        fallback_setting()
    end
  end

  def upsert_global(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_attrs()
      |> with_defaults_from_current()
      |> Map.put(:scope, @global_scope)

    case Repo.get_by(AppSetting, scope: @global_scope) do
      nil ->
        %AppSetting{}
        |> AppSetting.global_changeset(attrs)
        |> Repo.insert()

      %AppSetting{} = app_setting ->
        app_setting
        |> AppSetting.global_changeset(attrs)
        |> Repo.update()
    end
  end

  def global_map do
    app_setting = get_global()

    %{
      latitude: app_setting.latitude,
      longitude: app_setting.longitude,
      timezone: app_setting.timezone
    }
  end

  defp with_defaults_from_current(attrs) do
    current = get_global()

    current_attrs = %{
      latitude: current.latitude,
      longitude: current.longitude,
      timezone: current.timezone
    }

    Map.merge(current_attrs, attrs)
  end

  defp fallback_setting do
    config = Application.get_env(:hueworks, @config_key, %{})

    %AppSetting{
      scope: @global_scope,
      latitude: parse_number(config[:latitude] || config["latitude"]),
      longitude: parse_number(config[:longitude] || config["longitude"]),
      timezone: parse_timezone(config[:timezone] || config["timezone"])
    }
  end

  defp normalize_attrs(attrs) do
    %{
      latitude: parse_number(Map.get(attrs, :latitude) || Map.get(attrs, "latitude")),
      longitude: parse_number(Map.get(attrs, :longitude) || Map.get(attrs, "longitude")),
      timezone: parse_timezone(Map.get(attrs, :timezone) || Map.get(attrs, "timezone"))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp parse_number(value) when is_integer(value), do: value * 1.0
  defp parse_number(value) when is_float(value), do: value

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp parse_number(_value), do: nil

  defp parse_timezone(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_timezone(_value), do: nil
end
