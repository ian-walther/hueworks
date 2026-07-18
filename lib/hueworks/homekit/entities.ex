defmodule Hueworks.HomeKit.Entities do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.ControlTargets
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, Light, Area, Scene}

  def list_exposed_lights do
    Repo.all(
      from(l in Light,
        where:
          is_nil(l.canonical_light_id) and l.enabled == true and
            l.homekit_export_mode != :none,
        order_by: [asc: l.name, asc: l.id]
      )
    )
    |> Repo.preload(:area)
  end

  def list_exposed_groups do
    Repo.all(
      from(g in Group,
        where:
          is_nil(g.canonical_group_id) and g.enabled == true and
            g.homekit_export_mode != :none,
        order_by: [asc: g.name, asc: g.id]
      )
    )
    |> Repo.preload([:area, :lights])
  end

  def list_scenes do
    Repo.all(
      from(s in Scene,
        join: r in Area,
        on: r.id == s.area_id,
        preload: [area: r],
        order_by: [asc: r.name, asc: s.name, asc: s.id]
      )
    )
  end

  defdelegate fetch_entity(kind, id), to: ControlTargets

  defdelegate control_target(kind, id), to: ControlTargets

  def fetch_scene(id) when is_integer(id) do
    Repo.get(Scene, id)
    |> Repo.preload(:area)
  end

  def fetch_scene(_id), do: nil
end
