defmodule Hueworks.Schemas.BridgeImport do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bridge_imports" do
    belongs_to(:bridge, Hueworks.Schemas.Bridge)
    field(:raw_blob, :map)
    field(:normalized_blob, :map)
    field(:status, Ecto.Enum, values: [:fetched, :normalized, :reviewed, :applied])
    field(:imported_at, :utc_datetime)

    timestamps()
  end

  def changeset(import, attrs) do
    import
    |> cast(attrs, [:bridge_id, :raw_blob, :normalized_blob, :status, :imported_at])
    |> validate_required([:bridge_id, :raw_blob, :status, :imported_at])
  end
end
