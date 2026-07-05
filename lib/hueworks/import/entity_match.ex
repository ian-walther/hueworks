defmodule Hueworks.Import.EntityMatch do
  @moduledoc false

  alias Hueworks.Import.{Identifiers, Normalize}

  def match_existing(existing, incoming, type) when type in [:light, :group] do
    source_id = source_id(incoming)
    by_source_id = Enum.find(existing, &(&1.source_id == source_id))
    external_id = external_id(incoming, type)

    external_matches =
      Enum.filter(existing, &(&1.external_id == external_id and is_binary(external_id)))

    cond do
      by_source_id && Enum.any?(external_matches, &(&1.id != by_source_id.id)) ->
        :ambiguous

      by_source_id ->
        by_source_id

      true ->
        unique_external_match(existing, external_matches, source_id)
    end
  end

  defp unique_external_match(existing, [record], source_id) do
    if Enum.any?(existing, &(&1.id != record.id and &1.source_id == source_id)) do
      :ambiguous
    else
      record
    end
  end

  defp unique_external_match(_existing, [], _source_id), do: nil
  defp unique_external_match(_existing, _external_matches, _source_id), do: :ambiguous

  defp external_id(incoming, :light), do: Identifiers.light_external_id(incoming)
  defp external_id(incoming, :group), do: Identifiers.group_external_id(incoming)

  defp source_id(entity),
    do: entity |> Normalize.fetch(:source_id) |> Normalize.normalize_source_id()
end
