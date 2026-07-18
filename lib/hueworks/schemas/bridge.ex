defmodule Hueworks.Schemas.Bridge do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Schemas.Bridge.Credentials

  schema "bridges" do
    field(:type, Ecto.Enum, values: [:hue, :caseta, :ha, :z2m])
    field(:name, :string)
    field(:host, :string)
    field(:external_id, :string)

    embeds_one(:credentials, Credentials,
      source: :credentials,
      on_replace: :update,
      defaults_to_struct: true
    )

    field(:enabled, :boolean, default: true)
    field(:import_complete, :boolean, default: false)

    has_many(:bridge_imports, Hueworks.Schemas.BridgeImport)
    has_many(:external_spaces, Hueworks.Schemas.ExternalSpace)

    timestamps()
  end

  def changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:type, :name, :host, :external_id, :enabled, :import_complete])
    |> validate_required([:type, :name, :host])
    |> cast_bridge_credentials(attrs)
    |> unique_constraint([:type, :host])
    |> unique_constraint([:type, :external_id])
  end

  def credentials_struct(%__MODULE__{credentials: %Credentials{} = credentials}), do: credentials

  def credentials_struct(%__MODULE__{type: type, credentials: credentials}) do
    Credentials.load(type, credentials || %{})
  end

  defp cast_bridge_credentials(changeset, attrs) do
    type = get_field(changeset, :type)

    changeset
    |> cast_embed(:credentials,
      required: true,
      with: &Credentials.changeset(&1, &2, type)
    )
    |> ensure_credentials_present(attrs)
  end

  defp ensure_credentials_present(changeset, attrs) do
    if missing_credentials?(attrs) and is_nil(changeset.data.id) do
      add_error(changeset, :credentials, "can't be blank")
    else
      changeset
    end
  end

  defp missing_credentials?(attrs) when is_map(attrs) do
    not Map.has_key?(attrs, :credentials) and not Map.has_key?(attrs, "credentials")
  end

  defp missing_credentials?(_attrs), do: true
end
