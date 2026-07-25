defmodule Hueworks.Import.SpaceIdentity do
  @moduledoc false

  alias Hueworks.Import.Normalize

  def identity(space, bridge_type \\ nil) when is_map(space) do
    kind = Normalize.fetch(space, :kind) || default_kind(bridge_type)
    external_id = Normalize.fetch(space, :external_id) || Normalize.fetch(space, :source_id)

    {
      Normalize.normalize_space_kind(kind),
      Normalize.normalize_source_id(external_id)
    }
  end

  def attrs(space, bridge_type \\ nil) when is_map(space) do
    {kind, external_id} = identity(space, bridge_type)

    %{
      kind: kind,
      external_id: external_id,
      name: Normalize.fetch(space, :name),
      parent_kind:
        space
        |> Normalize.fetch(:parent_kind)
        |> Normalize.normalize_space_kind(),
      parent_external_id:
        space
        |> Normalize.fetch(:parent_external_id)
        |> Normalize.normalize_source_id(),
      metadata:
        space
        |> Normalize.fetch(:metadata)
        |> Normalize.normalize_map()
    }
  end

  defp default_kind(:hue), do: "hue_area"
  defp default_kind(:caseta), do: "caseta_area"
  defp default_kind(:ha), do: "ha_area"
  defp default_kind(:z2m), do: "z2m_group"
  defp default_kind(_type), do: "external_space"
end
