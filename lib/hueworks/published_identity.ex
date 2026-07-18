defmodule Hueworks.PublishedIdentity do
  @moduledoc false

  def space_identifiers(kind) when kind in [:room, :area] do
    token = Ecto.UUID.generate()
    prefix = Atom.to_string(kind)

    %{
      ha_device_identifier: "hueworks_#{prefix}_#{token}",
      ha_scene_select_identifier: "hueworks_#{prefix}_scene_select_#{token}"
    }
  end

  def room_device_identifier, do: new_identifier("hueworks_room")
  def room_scene_select_identifier, do: new_identifier("hueworks_room_scene_select")

  def area_device_identifier, do: new_identifier("hueworks_area")
  def area_scene_select_identifier, do: new_identifier("hueworks_area_scene_select")

  def fetch!(record, field) when is_map(record) and is_atom(field) do
    case Map.fetch(record, field) do
      {:ok, value} when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "missing persisted published identity #{inspect(field)}"
    end
  end

  defp new_identifier(prefix), do: "#{prefix}_#{Ecto.UUID.generate()}"
end
