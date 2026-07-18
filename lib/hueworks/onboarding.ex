defmodule Hueworks.Onboarding do
  @moduledoc """
  Derives setup progress from committed configuration.

  Only the selected path and explicit finish or dismissal are persisted. Bridge, import, Area,
  and scene progress remain authoritative in their existing tables.
  """

  alias Hueworks.{AppSettings, Bridges, Repo}
  alias Hueworks.Schemas.{Area, Group, Light, Scene}

  @paths [:ha_assisted, :direct]

  def status do
    app_setting = AppSettings.get_global()
    bridges = Bridges.list_bridges()
    bridge_count = length(bridges)
    area_count = Repo.aggregate(Area, :count)
    light_count = Repo.aggregate(Light, :count)
    group_count = Repo.aggregate(Group, :count)
    scene_count = Repo.aggregate(Scene, :count)
    pending_import_count = Enum.count(bridges, &(not Bridges.imported?(&1)))
    finished? = match?(%DateTime{}, app_setting.onboarding_completed_at)
    dismissed? = match?(%DateTime{}, app_setting.onboarding_dismissed_at)

    empty? =
      bridge_count == 0 and area_count == 0 and light_count == 0 and group_count == 0 and
        scene_count == 0

    %{
      path: parse_path(app_setting.onboarding_path),
      finished?: finished?,
      dismissed?: dismissed?,
      empty?: empty?,
      auto_open?: empty? and not finished? and not dismissed?,
      location_configured?: configured_location?(app_setting),
      bridge_count: bridge_count,
      pending_import_count: pending_import_count,
      area_count: area_count,
      light_count: light_count,
      group_count: group_count,
      scene_count: scene_count
    }
  end

  def choose_path(path) when path in @paths do
    AppSettings.update_onboarding_state(%{
      onboarding_path: Atom.to_string(path),
      onboarding_completed_at: nil,
      onboarding_dismissed_at: nil
    })
  end

  def choose_path(_path), do: {:error, :invalid_path}

  def finish do
    AppSettings.update_onboarding_state(%{
      onboarding_completed_at: now(),
      onboarding_dismissed_at: nil
    })
  end

  def dismiss do
    AppSettings.update_onboarding_state(%{
      onboarding_completed_at: nil,
      onboarding_dismissed_at: now()
    })
  end

  defp parse_path("ha_assisted"), do: :ha_assisted
  defp parse_path("direct"), do: :direct
  defp parse_path(_path), do: nil

  defp configured_location?(app_setting) do
    is_number(app_setting.latitude) and is_number(app_setting.longitude) and
      is_binary(app_setting.timezone) and app_setting.timezone != ""
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
