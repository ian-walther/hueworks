defmodule Hueworks.Import.SpaceMappings do
  @moduledoc false

  alias Hueworks.ExternalSpaces
  alias Hueworks.Import.{Normalize, ReviewPlan}
  alias Hueworks.Schemas.{Bridge, ExternalSpace}

  def sync_and_apply(%Bridge{} = bridge, normalized, plan, destination_by_source_id) do
    spaces = Enum.map(Normalize.external_spaces(normalized), &ensure_identity(&1, bridge.type))

    identity_by_source_id =
      Map.new(spaces, fn space ->
        {source_id(space), normalized_space_identity(space)}
      end)

    with {:ok, persisted_spaces} <- ExternalSpaces.sync_bridge_spaces(bridge, spaces),
         :ok <-
           apply_reviewed_mappings(
             persisted_spaces,
             normalized,
             plan,
             destination_by_source_id,
             identity_by_source_id
           ) do
      :ok = apply_explicit_space_mappings(persisted_spaces, plan)
      {:ok, ExternalSpaces.mapping_ids_for_bridge(bridge)}
    end
  end

  def identity(space, fallback_type \\ nil)

  def identity(space, fallback_type) when is_map(space) do
    space
    |> ensure_identity(fallback_type)
    |> normalized_space_identity()
  end

  def key({kind, external_id}) when is_binary(kind) and is_binary(external_id) do
    [kind, external_id]
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def key(space) when is_map(space), do: space |> identity() |> key()

  def target_id_for(entry, destination_by_source_id, entity_plan, mapped_space_ids) do
    case explicit_target(entity_plan, entry) do
      :unassigned ->
        nil

      target_id when is_integer(target_id) ->
        target_id

      nil ->
        destination_from_import(entry, destination_by_source_id) ||
          destination_from_mappings(entry, mapped_space_ids)
    end
  end

  def apply_plan_defaults(plan, normalized) when is_map(plan) and is_map(normalized) do
    bridge = Normalize.fetch(normalized, :bridge) || %{}
    bridge_id = Normalize.fetch(bridge, :id)
    bridge_type = Normalize.fetch(bridge, :type)

    if is_integer(bridge_id) do
      mappings = ExternalSpaces.mapping_ids_for_bridge(bridge_id)

      plan =
        normalized
        |> Normalize.fetch(:areas)
        |> Kernel.||([])
        |> Enum.reduce(plan, fn source_space, acc ->
          source_id = source_id(source_space)
          identity = source_space |> ensure_identity(bridge_type) |> normalized_space_identity()

          case Map.get(mappings, identity) do
            area_id when is_integer(area_id) ->
              ReviewPlan.put_area(acc, source_id, %{
                "action" => "merge",
                "target_area_id" => Integer.to_string(area_id)
              })

            _ ->
              acc
          end
        end)

      normalized
      |> Normalize.external_spaces()
      |> Enum.reduce(plan, fn space, acc ->
        identity = identity(space, bridge_type)

        case Map.get(mappings, identity) do
          area_id when is_integer(area_id) ->
            ReviewPlan.put_space_mapping(acc, key(identity), %{
              "kind" => elem(identity, 0),
              "external_id" => elem(identity, 1),
              "action" => "map",
              "target_area_id" => Integer.to_string(area_id)
            })

          _ ->
            acc
        end
      end)
    else
      plan
    end
  end

  def apply_suggestions(plan, %{spaces: suggestions}) when is_map(suggestions) do
    Enum.reduce(suggestions, plan, fn {_identity, suggestion}, acc ->
      if suggestion.preselect? and is_integer(suggestion.suggested_area_id) do
        target_area_id = Integer.to_string(suggestion.suggested_area_id)
        source_id = suggestion.external_id

        acc
        |> ReviewPlan.put_space_mapping(key({suggestion.kind, source_id}), %{
          "kind" => suggestion.kind,
          "external_id" => source_id,
          "action" => "map",
          "target_area_id" => target_area_id
        })
        |> maybe_put_placement_area(suggestion, target_area_id)
      else
        acc
      end
    end)
  end

  def apply_suggestions(plan, _suggestions), do: plan

  defp apply_reviewed_mappings(
         persisted_spaces,
         normalized,
         plan,
         destination_by_source_id,
         identity_by_source_id
       ) do
    spaces_by_identity =
      Map.new(persisted_spaces, fn space -> {{space.kind, space.external_id}, space} end)

    normalized
    |> Normalize.fetch(:areas)
    |> Kernel.||([])
    |> Enum.each(fn source_space ->
      source_id = source_id(source_space)
      target_area_id = Map.get(destination_by_source_id, source_id)

      if is_integer(target_area_id) and reviewed_mapping?(plan, source_id) do
        identity = Map.get(identity_by_source_id, source_id)

        with %ExternalSpace{} = persisted <- Map.get(spaces_by_identity, identity),
             {:ok, _mapping} <- ExternalSpaces.put_mapping(persisted, target_area_id) do
          :ok
        else
          nil ->
            raise "normalized placement space is missing from external-space inventory"

          {:error, changeset} ->
            raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
        end
      end
    end)

    :ok
  end

  defp apply_explicit_space_mappings(persisted_spaces, plan) do
    spaces_by_identity =
      Map.new(persisted_spaces, fn space -> {{space.kind, space.external_id}, space} end)

    plan
    |> Normalize.fetch(:external_space_mappings)
    |> Kernel.||(%{})
    |> Enum.each(fn {_key, entry} ->
      kind = Normalize.fetch(entry, :kind) |> Normalize.normalize_space_kind()
      external_id = Normalize.fetch(entry, :external_id) |> Normalize.normalize_source_id()
      target_area_id = Normalize.fetch(entry, :target_area_id) |> parse_integer()

      if Normalize.fetch(entry, :action) == "map" and is_integer(target_area_id) do
        case Map.get(spaces_by_identity, {kind, external_id}) do
          %ExternalSpace{} = space ->
            case ExternalSpaces.put_mapping(space, target_area_id) do
              {:ok, _mapping} ->
                :ok

              {:error, changeset} ->
                raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
            end

          nil ->
            raise "reviewed external-space mapping refers to a missing source space"
        end
      end
    end)

    :ok
  end

  defp reviewed_mapping?(plan, source_id) do
    area_plan = Normalize.fetch(plan, :areas) || %{}

    case Normalize.fetch(area_plan, source_id) do
      %{} = entry -> Normalize.fetch(entry, :action) in ["create", "merge"]
      _ -> false
    end
  end

  defp explicit_target(entity_plan, entry) do
    source_id = source_id(entry)
    plan_entry = if is_binary(source_id), do: Normalize.fetch(entity_plan, source_id), else: nil

    case Normalize.fetch(plan_entry, :target_area_id) do
      "unassigned" -> :unassigned
      value -> parse_integer(value)
    end
  end

  defp destination_from_import(entry, destination_by_source_id) do
    entry
    |> Normalize.fetch(:area_source_id)
    |> Normalize.normalize_source_id()
    |> then(&Map.get(destination_by_source_id, &1))
  end

  defp destination_from_mappings(entry, mapped_space_ids) do
    entry
    |> Normalize.entity_space_refs()
    |> Enum.find_value(fn ref ->
      kind = Normalize.fetch(ref, :kind) |> Normalize.normalize_space_kind()
      external_id = Normalize.fetch(ref, :external_id) |> Normalize.normalize_source_id()
      Map.get(mapped_space_ids, {kind, external_id})
    end)
  end

  defp normalized_space_identity(space) do
    kind = Normalize.fetch(space, :kind) |> Normalize.normalize_space_kind()

    external_id =
      Normalize.fetch(space, :external_id) || Normalize.fetch(space, :source_id)

    {kind, Normalize.normalize_source_id(external_id)}
  end

  defp ensure_identity(space, bridge_type) when is_map(space) do
    space
    |> Map.put_new(:kind, default_kind(bridge_type))
    |> Map.put_new(:external_id, Normalize.fetch(space, :source_id))
  end

  defp default_kind(:hue), do: "hue_area"
  defp default_kind(:caseta), do: "caseta_area"
  defp default_kind(:ha), do: "ha_area"
  defp default_kind(:z2m), do: "z2m_group"
  defp default_kind(_type), do: "external_space"

  defp maybe_put_placement_area(plan, %{kind: kind, external_id: source_id}, target_area_id)
       when kind in ["hue_area", "caseta_area", "ha_area"] do
    ReviewPlan.put_area(plan, source_id, %{
      "action" => "merge",
      "target_area_id" => target_area_id
    })
  end

  defp maybe_put_placement_area(plan, _suggestion, _target_area_id), do: plan

  defp source_id(entry) do
    entry
    |> Normalize.fetch(:source_id)
    |> Normalize.normalize_source_id()
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil
end
