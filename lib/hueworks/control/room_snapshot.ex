defmodule Hueworks.Control.RoomSnapshot do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Control.DesiredState
  alias Hueworks.Control.State, as: PhysicalState
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light}

  def load(room_id) when is_integer(room_id) do
    room_lights =
      Repo.all(
        from(l in Light,
          where: l.room_id == ^room_id,
          select: %{
            id: l.id,
            bridge_id: l.bridge_id,
            supports_temp: l.supports_temp,
            reported_min_kelvin: l.reported_min_kelvin,
            reported_max_kelvin: l.reported_max_kelvin,
            actual_min_kelvin: l.actual_min_kelvin,
            actual_max_kelvin: l.actual_max_kelvin,
            extended_kelvin_range: l.extended_kelvin_range
          }
        )
      )

    %{
      room_id: room_id,
      room_lights: room_lights,
      desired_by_light:
        Map.new(room_lights, fn light ->
          {light.id, DesiredState.get(:light, light.id)}
        end),
      physical_by_light:
        Map.new(room_lights, fn light ->
          {light.id, PhysicalState.get(:light, light.id) || %{}}
        end),
      group_memberships: load_group_memberships(room_id)
    }
  end

  defp load_group_memberships(room_id) do
    groups =
      Repo.all(
        from(g in Group,
          where: g.room_id == ^room_id,
          select: %{id: g.id, bridge_id: g.bridge_id}
        )
      )

    memberships =
      Repo.all(
        from(gl in GroupLight,
          join: g in Group,
          on: g.id == gl.group_id,
          where: g.room_id == ^room_id,
          select: {g.id, gl.light_id}
        )
      )

    base =
      Enum.map(groups, fn group ->
        %{id: group.id, bridge_id: group.bridge_id, lights: MapSet.new()}
      end)

    Enum.reduce(memberships, base, fn {group_id, light_id}, acc ->
      Enum.map(acc, fn group ->
        if group.id == group_id do
          %{group | lights: MapSet.put(group.lights, light_id)}
        else
          group
        end
      end)
    end)
  end
end
