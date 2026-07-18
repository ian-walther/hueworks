defmodule Hueworks.ExternalSpaces do
  @moduledoc """
  Stores source-reported spaces separately from user-authored HueWorks Area mappings.

  Synchronization refreshes source facts without deleting unseen spaces or changing mappings.
  That preserves rename diagnostics and keeps temporary source omissions nondestructive.
  """

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.Normalize
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Area, Bridge, ExternalSpace, ExternalSpaceMapping}

  def list_for_bridge(%Bridge{id: bridge_id}), do: list_for_bridge(bridge_id)

  def list_for_bridge(bridge_id) when is_integer(bridge_id) do
    Repo.all(
      from(es in ExternalSpace,
        where: es.bridge_id == ^bridge_id,
        order_by: [asc: es.kind, asc: es.name, asc: es.external_id],
        preload: [:parent_external_space, mapping: :area]
      )
    )
  end

  def get_by_identity(bridge_or_id, kind, external_id)

  def get_by_identity(%Bridge{id: bridge_id}, kind, external_id) do
    get_by_identity(bridge_id, kind, external_id)
  end

  def get_by_identity(bridge_id, kind, external_id)
      when is_integer(bridge_id) and is_binary(kind) and is_binary(external_id) do
    Repo.get_by(ExternalSpace,
      bridge_id: bridge_id,
      kind: kind,
      external_id: external_id
    )
  end

  def mapped_area_id(bridge_or_id, kind, external_id)

  def mapped_area_id(%Bridge{id: bridge_id}, kind, external_id) do
    mapped_area_id(bridge_id, kind, external_id)
  end

  def mapped_area_id(bridge_id, kind, external_id)
      when is_integer(bridge_id) and is_binary(kind) and is_binary(external_id) do
    Repo.one(
      from(es in ExternalSpace,
        join: mapping in ExternalSpaceMapping,
        on: mapping.external_space_id == es.id,
        where:
          es.bridge_id == ^bridge_id and es.kind == ^kind and
            es.external_id == ^external_id,
        select: mapping.area_id
      )
    )
  end

  def sync_bridge_spaces(%Bridge{} = bridge, spaces, opts \\ []) when is_list(spaces) do
    seen_at = Keyword.get(opts, :seen_at, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

    Repo.transaction(fn ->
      identities =
        spaces
        |> Enum.map(&normalize_space/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(&{&1.kind, &1.external_id})

      by_identity =
        Map.new(identities, fn attrs ->
          space = upsert_space!(bridge.id, attrs, seen_at)
          {{space.kind, space.external_id}, space}
        end)

      Enum.each(identities, fn attrs ->
        space = Map.fetch!(by_identity, {attrs.kind, attrs.external_id})
        parent_id = parent_id(attrs, by_identity)

        if space.parent_external_space_id != parent_id do
          space
          |> ExternalSpace.changeset(%{parent_external_space_id: parent_id})
          |> Repo.update!()
        end
      end)

      list_for_bridge(bridge.id)
    end)
  end

  def put_mapping(%ExternalSpace{} = external_space, %Area{id: area_id}) do
    put_mapping(external_space, area_id)
  end

  def put_mapping(%ExternalSpace{id: external_space_id}, area_id) when is_integer(area_id) do
    case Repo.get_by(ExternalSpaceMapping, external_space_id: external_space_id) do
      nil ->
        %ExternalSpaceMapping{}
        |> ExternalSpaceMapping.changeset(%{
          external_space_id: external_space_id,
          area_id: area_id
        })
        |> Repo.insert()

      mapping ->
        mapping
        |> ExternalSpaceMapping.changeset(%{area_id: area_id})
        |> Repo.update()
    end
  end

  def remove_mapping(%ExternalSpace{id: external_space_id}) do
    case Repo.get_by(ExternalSpaceMapping, external_space_id: external_space_id) do
      nil -> :ok
      mapping -> mapping |> Repo.delete() |> normalize_delete_result()
    end
  end

  def stale?(%ExternalSpace{last_seen_at: last_seen_at}, %DateTime{} = latest_sync_at) do
    DateTime.before?(last_seen_at, latest_sync_at)
  end

  defp upsert_space!(bridge_id, attrs, seen_at) do
    identity = [bridge_id: bridge_id, kind: attrs.kind, external_id: attrs.external_id]

    values = %{
      bridge_id: bridge_id,
      kind: attrs.kind,
      external_id: attrs.external_id,
      name: attrs.name,
      metadata: attrs.metadata,
      last_seen_at: seen_at
    }

    case Repo.get_by(ExternalSpace, identity) do
      nil ->
        %ExternalSpace{}
        |> ExternalSpace.changeset(values)
        |> Repo.insert!()

      existing ->
        existing
        |> ExternalSpace.changeset(values)
        |> Repo.update!()
    end
  end

  defp normalize_space(space) when is_map(space) do
    kind = Normalize.fetch(space, :kind) |> normalize_text()
    external_id = Normalize.fetch(space, :external_id) |> Normalize.normalize_source_id()
    name = Normalize.fetch(space, :name) |> normalize_text()

    if is_binary(kind) and is_binary(external_id) do
      %{
        kind: kind,
        external_id: external_id,
        name: name || external_id,
        parent_kind: Normalize.fetch(space, :parent_kind) |> normalize_text(),
        parent_external_id:
          Normalize.fetch(space, :parent_external_id) |> Normalize.normalize_source_id(),
        metadata: Normalize.fetch(space, :metadata) |> Normalize.normalize_map()
      }
    end
  end

  defp normalize_space(_space), do: nil

  defp parent_id(%{parent_kind: kind, parent_external_id: external_id}, by_identity)
       when is_binary(kind) and is_binary(external_id) do
    case Map.get(by_identity, {kind, external_id}) do
      %ExternalSpace{id: id} -> id
      nil -> nil
    end
  end

  defp parent_id(_attrs, _by_identity), do: nil

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_text(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_text(_value), do: nil

  defp normalize_delete_result({:ok, _mapping}), do: :ok
  defp normalize_delete_result({:error, changeset}), do: {:error, changeset}
end
