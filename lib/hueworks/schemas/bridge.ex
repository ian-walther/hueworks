defmodule Hueworks.Schemas.Bridge do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Schemas.Bridge.Credentials

  schema "bridges" do
    field(:type, Ecto.Enum, values: [:hue, :caseta, :ha, :z2m])
    field(:name, :string)
    field(:host, :string)
    field(:credentials, :map)
    field(:enabled, :boolean, default: true)
    field(:import_complete, :boolean, default: false)

    has_many(:bridge_imports, Hueworks.Schemas.BridgeImport)

    timestamps()
  end

  def changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:type, :name, :host, :credentials, :enabled, :import_complete])
    |> validate_required([:type, :name, :host, :credentials])
    |> validate_credentials()
    |> unique_constraint([:type, :host])
  end

  def credentials_struct(%__MODULE__{type: type, credentials: credentials}) do
    Credentials.load(type, credentials || %{})
  end

  defp validate_credentials(changeset) do
    type = get_field(changeset, :type)
    credentials = get_field(changeset, :credentials) || %{}

    case Credentials.normalize(type, credentials) do
      {:ok, normalized} ->
        put_change(changeset, :credentials, normalized)

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {key, message}, acc ->
          add_error(acc, :credentials, "#{key} #{message}")
        end)
    end
  end
end
