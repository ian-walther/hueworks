defmodule Hueworks.Import.Duplicates do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Hueworks.Import.{EntityMatch, Identifiers, Normalize, Source}
  alias Hueworks.Repo
  alias Hueworks.Schemas.{Group, GroupLight, Light}

  @native_sources [:hue, :caseta, :z2m]

  def reject_hueworks_exported(entities) do
    Enum.reject(entities, fn entity ->
      source = Source.normalize(Normalize.fetch(entity, :source))
      metadata = Normalize.fetch(entity, :metadata) || %{}
      unique_id = Normalize.fetch(metadata, :unique_id) || Normalize.fetch(metadata, "unique_id")

      source == :ha and is_binary(unique_id) and String.starts_with?(unique_id, "hueworks_")
    end)
  end

  def light_targets(lights) do
    native_lights =
      Repo.all(
        from(l in Light,
          where: l.source in ^@native_sources and is_nil(l.canonical_light_id)
        )
      )

    indexes = %{
      "mac" => identifier_index(native_lights, "mac"),
      "serial" => identifier_index(native_lights, "serial"),
      "ieee" => identifier_index(native_lights, "ieee")
    }

    Enum.reduce(lights, %{}, fn light, acc ->
      if Source.normalize(Normalize.fetch(light, :source)) == :ha do
        case unique_native_light_match(light, indexes) do
          nil -> acc
          id -> Map.put(acc, source_id(light), id)
        end
      else
        acc
      end
    end)
  end

  def existing_light_canonical_targets(bridge_id, lights) when is_integer(bridge_id) do
    source_ids =
      lights
      |> Enum.map(&source_id/1)
      |> Enum.filter(&is_binary/1)

    external_ids =
      lights
      |> Enum.map(&light_external_id/1)
      |> Enum.filter(&is_binary/1)

    existing_lights =
      Repo.all(
        from(l in Light,
          where:
            l.bridge_id == ^bridge_id and
              (l.source_id in ^source_ids or l.external_id in ^external_ids)
        )
      )

    Enum.reduce(lights, %{}, fn light, acc ->
      source_id = source_id(light)

      case EntityMatch.match_existing(existing_lights, light, :light) do
        %Light{} = record when is_binary(source_id) ->
          Map.put(acc, source_id, record.canonical_light_id || record.id)

        _ ->
          acc
      end
    end)
  end

  def existing_light_canonical_targets(_bridge_id, _lights), do: %{}

  def group_target(group, source_id_to_canonical_light_id) do
    if Source.normalize(Normalize.fetch(group, :source)) == :ha do
      with {:ok, member_set} <- canonical_member_set(group, source_id_to_canonical_light_id),
           group_id when is_integer(group_id) <- unique_native_group_match(member_set) do
        group_id
      else
        _ -> nil
      end
    else
      nil
    end
  end

  defp identifier_index(lights, key) do
    Enum.reduce(lights, %{}, fn light, acc ->
      case metadata_identifier(light, key) do
        nil -> acc
        value -> Map.update(acc, value, [light.id], &[light.id | &1])
      end
    end)
  end

  defp unique_native_light_match(light, indexes) do
    ["mac", "serial", "ieee"]
    |> Enum.find_value(fn key ->
      value = normalized_identifier(light, key)

      case if(is_binary(value), do: Map.get(indexes[key], value, []), else: []) |> Enum.uniq() do
        [id] -> id
        _ -> nil
      end
    end)
  end

  defp canonical_member_set(group, source_id_to_canonical_light_id) do
    members =
      group
      |> Normalize.fetch(:metadata)
      |> Kernel.||(%{})
      |> Normalize.fetch(:members)
      |> Normalize.normalize_list()

    ids =
      Enum.map(
        members,
        &Map.get(source_id_to_canonical_light_id, Normalize.normalize_source_id(&1))
      )

    cond do
      ids == [] -> :error
      Enum.any?(ids, &is_nil/1) -> :error
      true -> {:ok, MapSet.new(ids)}
    end
  end

  defp unique_native_group_match(member_set) do
    matches =
      Repo.all(
        from(gl in GroupLight,
          join: g in Group,
          on: g.id == gl.group_id,
          where: g.source in ^@native_sources and is_nil(g.canonical_group_id),
          select: {gl.group_id, gl.light_id}
        )
      )
      |> Enum.group_by(fn {group_id, _light_id} -> group_id end, fn {_group_id, light_id} ->
        light_id
      end)
      |> Enum.filter(fn {_group_id, light_ids} ->
        MapSet.equal?(member_set, MapSet.new(light_ids))
      end)
      |> Enum.map(fn {group_id, _light_ids} -> group_id end)

    case matches do
      [group_id] -> group_id
      _ -> nil
    end
  end

  defp normalized_identifier(entity, key) do
    identifiers = Normalize.fetch(entity, :identifiers) || %{}
    value = Normalize.fetch(identifiers, key)
    if is_binary(value) and value != "", do: value
  end

  defp light_external_id(light), do: Identifiers.light_external_id(light)

  defp metadata_identifier(%{metadata: metadata}, key) when is_map(metadata) do
    identifiers = metadata["identifiers"] || metadata[:identifiers] || %{}
    value = identifiers[key] || identifiers[String.to_atom(key)]
    if is_binary(value) and value != "", do: value
  end

  defp metadata_identifier(_entity, _key), do: nil

  defp source_id(entity),
    do: entity |> Normalize.fetch(:source_id) |> Normalize.normalize_source_id()
end
