defmodule Hueworks.Import.IdentifierIndex do
  @moduledoc false

  alias Hueworks.Import.Normalize

  @keys ["mac", "serial", "ieee"]

  def build(records, opts \\ []) do
    identifier_fun = Keyword.get(opts, :identifier, &metadata_identifier/2)

    Enum.into(@keys, %{}, fn key ->
      {key, identifier_index(records, key, identifier_fun)}
    end)
  end

  def unique_match(indexes, key, value) do
    case if(is_binary(value), do: Map.get(indexes[key], value, []), else: []) |> Enum.uniq() do
      [id] -> id
      _ -> nil
    end
  end

  def metadata_identifier(%{metadata: metadata}, key) when is_map(metadata) do
    identifiers = metadata["identifiers"] || metadata[:identifiers] || %{}
    value = identifiers[key] || identifiers[String.to_atom(key)]
    if is_binary(value) and value != "", do: value
  end

  def metadata_identifier(_entity, _key), do: nil

  def normalized_identifier(entity, key) do
    identifiers = Normalize.fetch(entity, :identifiers) || %{}
    value = Normalize.fetch(identifiers, key)
    if is_binary(value) and value != "", do: value
  end

  defp identifier_index(records, key, identifier_fun) do
    Enum.reduce(records, %{}, fn record, acc ->
      case identifier_fun.(record, key) do
        nil -> acc
        value -> Map.update(acc, value, [record.id], &[record.id | &1])
      end
    end)
  end
end
