defmodule Hueworks.Schemas.LightState do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Circadian.Config, as: CircadianConfig

  schema "light_states" do
    field(:name, :string)
    field(:type, Ecto.Enum, values: [:manual, :circadian])
    field(:config, :map, default: %{})

    has_many(:scene_components, Hueworks.Schemas.SceneComponent)

    timestamps()
  end

  def changeset(light_state, attrs) do
    light_state
    |> cast(attrs, [:name, :type, :config])
    |> validate_required([:name, :type])
    |> validate_type_config()
  end

  defp validate_type_config(changeset) do
    case get_field(changeset, :type) do
      :circadian ->
        validate_circadian_config(changeset)

      _ ->
        changeset
    end
  end

  defp validate_circadian_config(changeset) do
    config = get_field(changeset, :config) || %{}

    case CircadianConfig.normalize(config) do
      {:ok, normalized} ->
        put_change(changeset, :config, normalized)

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {key, message}, acc ->
          add_error(acc, :config, "#{key} #{message}")
        end)
    end
  end
end
