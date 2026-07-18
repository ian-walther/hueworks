defmodule Hueworks.Import.SpaceSuggestions do
  @moduledoc """
  Produces review evidence for native-space placement from a mapped HA inventory.

  No suggestion mutates a review plan. Full-coverage agreement is safe to preselect during a
  review; partial agreement requires confirmation; ambiguity and conflict remain unassigned.
  """

  alias Hueworks.{Bridges, ExternalSpaces}
  alias Hueworks.Import.Normalize
  alias Hueworks.Schemas.Bridge

  def build_from_available_ha(%Bridge{type: type} = native_bridge, native_normalized)
      when type != :ha do
    candidates =
      Bridges.list_bridges()
      |> Enum.filter(&(&1.type == :ha and &1.enabled))
      |> Enum.flat_map(fn bridge ->
        case Bridges.latest_import(bridge) do
          %{normalized_blob: normalized} when is_map(normalized) -> [{bridge, normalized}]
          _ -> []
        end
      end)

    case candidates do
      [{ha_bridge, ha_normalized}] ->
        {:ok, build(native_bridge, native_normalized, ha_bridge, ha_normalized)}

      [] ->
        {:error, :ha_inventory_unavailable}

      _ ->
        {:error, :multiple_ha_inventories}
    end
  end

  def build_from_available_ha(_bridge, _normalized), do: {:error, :not_native_bridge}

  @identifier_keys ["mac", "serial", "ieee"]

  def build(
        %Bridge{} = native_bridge,
        native_normalized,
        %Bridge{type: :ha} = ha_bridge,
        ha_normalized
      ) do
    ha_lights = Normalize.fetch(ha_normalized, :lights) || []
    ha_mappings = ExternalSpaces.mapping_ids_for_bridge(ha_bridge)
    native_mappings = ExternalSpaces.mapping_ids_for_bridge(native_bridge)
    matches = match_native_lights(native_normalized, ha_lights, ha_mappings)

    spaces =
      native_normalized
      |> Normalize.external_spaces()
      |> Enum.map(fn space ->
        suggestion_for_space(
          space,
          native_normalized,
          matches,
          native_mappings,
          native_bridge.type
        )
      end)

    %{
      spaces: Map.new(spaces, &{&1.key, &1}),
      entities: matches
    }
  end

  defp match_native_lights(native_normalized, ha_lights, ha_mappings) do
    ha_index = build_identifier_index(ha_lights)

    native_normalized
    |> Normalize.fetch(:lights)
    |> Kernel.||([])
    |> Map.new(fn native_light ->
      source_id = source_id(native_light)
      {source_id, match_light(native_light, ha_lights, ha_index, ha_mappings)}
    end)
  end

  defp match_light(native_light, ha_lights, ha_index, ha_mappings) do
    candidate_ids =
      @identifier_keys
      |> Enum.flat_map(fn key ->
        case normalized_identifier(native_light, key) do
          nil -> []
          value -> Map.get(ha_index, {key, value}, [])
        end
      end)
      |> Enum.uniq()

    case candidate_ids do
      [] ->
        %{status: :unmatched, target_area_id: nil, ha_source_id: nil, identifiers: []}

      [ha_source_id] ->
        ha_light = Enum.find(ha_lights, &(source_id(&1) == ha_source_id))
        mapped_evidence = mapped_evidence(ha_light, ha_mappings)

        %{
          status: mapped_evidence.status,
          target_area_id: mapped_evidence.target_area_id,
          ha_source_id: ha_source_id,
          identifiers: matching_identifiers(native_light, ha_light),
          space_evidence: mapped_evidence.space_evidence
        }

      _ ->
        %{
          status: :ambiguous_identity,
          target_area_id: nil,
          ha_source_id: nil,
          candidate_source_ids: candidate_ids,
          identifiers: []
        }
    end
  end

  defp suggestion_for_space(
         space,
         native_normalized,
         matches,
         native_mappings,
         bridge_type
       ) do
    identity = space_identity(space, bridge_type)
    members = member_source_ids(space, native_normalized, bridge_type)
    member_matches = Enum.map(members, &Map.get(matches, &1, %{status: :unmatched}))
    ambiguous? = Enum.any?(member_matches, &(&1.status == :ambiguous_identity))

    matched =
      Enum.filter(member_matches, fn match ->
        match.status == :matched and is_integer(match.target_area_id)
      end)

    inferred_targets = matched |> Enum.map(& &1.target_area_id) |> Enum.uniq()
    saved_target = Map.get(native_mappings, identity)
    inferred_target = List.first(inferred_targets)

    status =
      cond do
        ambiguous? ->
          :ambiguous_identity

        length(inferred_targets) > 1 ->
          :conflict

        is_integer(saved_target) and is_integer(inferred_target) and
            saved_target != inferred_target ->
          :conflict

        matched == [] ->
          :no_evidence

        length(matched) == length(members) ->
          :confident

        true ->
          :partial
      end

    %{
      key: identity,
      kind: elem(identity, 0),
      external_id: elem(identity, 1),
      name: Normalize.fetch(space, :name),
      status: status,
      member_count: length(members),
      matched_count: length(matched),
      suggested_area_id: inferred_target,
      saved_area_id: saved_target,
      preselect?: status == :confident,
      evidence: member_matches
    }
  end

  defp mapped_evidence(nil, _mappings) do
    %{status: :unmatched, target_area_id: nil, space_evidence: []}
  end

  defp mapped_evidence(ha_light, mappings) do
    evidence =
      ha_light
      |> Normalize.entity_space_refs()
      |> Enum.map(fn ref ->
        identity = {
          Normalize.fetch(ref, :kind) |> Normalize.normalize_space_kind(),
          Normalize.fetch(ref, :external_id) |> Normalize.normalize_source_id()
        }

        %{
          identity: identity,
          relationship: Normalize.fetch(ref, :relationship),
          area_id: Map.get(mappings, identity)
        }
      end)

    case Enum.find(evidence, &is_integer(&1.area_id)) do
      nil -> %{status: :unmapped, target_area_id: nil, space_evidence: evidence}
      selected -> %{status: :matched, target_area_id: selected.area_id, space_evidence: evidence}
    end
  end

  defp member_source_ids(space, normalized, bridge_type) when bridge_type in [:z2m, :hue] do
    kind = Normalize.fetch(space, :kind)

    if kind in ["z2m_group", "hue_zone"] do
      group_member_source_ids(space, normalized)
    else
      placement_member_source_ids(space, normalized)
    end
  end

  defp member_source_ids(space, normalized, _bridge_type) do
    placement_member_source_ids(space, normalized)
  end

  defp group_member_source_ids(space, normalized) do
    external_id = Normalize.fetch(space, :external_id) || Normalize.fetch(space, :source_id)

    normalized
    |> Normalize.fetch(:groups)
    |> Kernel.||([])
    |> Enum.find(&(source_id(&1) == Normalize.normalize_source_id(external_id)))
    |> case do
      nil ->
        []

      group ->
        group
        |> Normalize.fetch(:metadata)
        |> Normalize.fetch(:members)
        |> Normalize.normalize_list()
    end
  end

  defp placement_member_source_ids(space, normalized) do
    source_space_id =
      Normalize.fetch(space, :source_id) || Normalize.fetch(space, :external_id)

    normalized
    |> Normalize.fetch(:lights)
    |> Kernel.||([])
    |> Enum.filter(fn light ->
      Normalize.normalize_source_id(Normalize.fetch(light, :area_source_id)) ==
        Normalize.normalize_source_id(source_space_id)
    end)
    |> Enum.map(&source_id/1)
  end

  defp build_identifier_index(ha_lights) do
    Enum.reduce(ha_lights, %{}, fn light, acc ->
      Enum.reduce(@identifier_keys, acc, fn key, inner ->
        case normalized_identifier(light, key) do
          nil -> inner
          value -> Map.update(inner, {key, value}, [source_id(light)], &[source_id(light) | &1])
        end
      end)
    end)
  end

  defp matching_identifiers(left, right) do
    Enum.filter(@identifier_keys, fn key ->
      value = normalized_identifier(left, key)
      is_binary(value) and value == normalized_identifier(right, key)
    end)
  end

  defp normalized_identifier(entity, key) do
    entity
    |> Normalize.fetch(:identifiers)
    |> Kernel.||(%{})
    |> Normalize.fetch(key)
    |> case do
      value when is_binary(value) and value != "" -> String.downcase(value)
      _ -> nil
    end
  end

  defp space_identity(space, bridge_type) do
    kind = Normalize.fetch(space, :kind) || default_kind(bridge_type)
    external_id = Normalize.fetch(space, :external_id) || Normalize.fetch(space, :source_id)
    {Normalize.normalize_space_kind(kind), Normalize.normalize_source_id(external_id)}
  end

  defp default_kind(:hue), do: "hue_area"
  defp default_kind(:caseta), do: "caseta_area"
  defp default_kind(:z2m), do: "z2m_group"
  defp default_kind(_type), do: "external_space"

  defp source_id(entity) do
    entity
    |> Normalize.fetch(:source_id)
    |> Normalize.normalize_source_id()
  end
end
