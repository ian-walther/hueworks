defmodule Hueworks.Import.Rooms do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.Normalize
  alias Hueworks.Repo
  alias Hueworks.Schemas.Room
  alias Hueworks.Util

  def upsert(room, plan) do
    case Normalize.fetch(plan, :action) || "create" do
      "skip" ->
        nil

      "merge" ->
        plan
        |> Normalize.fetch(:target_room_id)
        |> Util.parse_optional_integer()
        |> then(fn
          nil -> nil
          id -> if Repo.get(Room, id), do: id
        end)

      _ ->
        name = Normalize.fetch(room, :name) || "Room"
        normalized_name = Normalize.normalize_room_name(name)

        case Repo.one(from(r in Room, where: fragment("lower(?)", r.name) == ^normalized_name)) do
          nil ->
            %Room{}
            |> Room.changeset(%{
              name: name,
              metadata: %{"normalized_name" => normalized_name}
            })
            |> Repo.insert!()
            |> Map.fetch!(:id)

          room ->
            room.id
        end
    end
  end

  def target_id_for(entry, room_map, plan_map) do
    source_id =
      entry
      |> Normalize.fetch(:source_id)
      |> Normalize.normalize_source_id()

    plan_entry = if is_binary(source_id), do: Normalize.fetch(plan_map, source_id), else: nil

    case plan_entry |> Normalize.fetch(:target_room_id) |> Util.parse_optional_integer() do
      id when is_integer(id) ->
        id

      _ ->
        entry
        |> Normalize.fetch(:room_source_id)
        |> Normalize.normalize_source_id()
        |> then(&Map.get(room_map, &1))
    end
  end
end
