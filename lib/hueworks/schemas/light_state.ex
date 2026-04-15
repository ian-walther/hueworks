defmodule Hueworks.Schemas.LightState do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Circadian.Config, as: CircadianConfig
  alias Hueworks.Schemas.LightState.Config
  alias Hueworks.Schemas.LightState.ManualConfig

  schema "light_states" do
    field(:name, :string)
    field(:type, Ecto.Enum, values: [:manual, :circadian])
    embeds_one(:config, Config, source: :config, on_replace: :update, defaults_to_struct: true)

    has_many(:scene_components, Hueworks.Schemas.SceneComponent)

    timestamps()
  end

  def changeset(light_state, attrs) do
    light_state
    |> cast(attrs, [:name, :type])
    |> validate_required([:name, :type])
    |> cast_type_config(attrs)
  end

  def manual_config(%__MODULE__{config: config}), do: manual_config(config)
  def manual_config(%Config{} = config), do: Config.manual_map(config)
  def manual_config(config), do: ManualConfig.canonical_map(config)

  def manual_mode(%__MODULE__{} = light_state), do: manual_mode(light_state.config)
  def manual_mode(%Config{} = config), do: Config.manual_mode(config)
  def manual_mode(config), do: ManualConfig.mode(config)

  def circadian_config(%__MODULE__{config: config}), do: circadian_config(config)
  def circadian_config(%Config{} = config), do: Config.circadian_struct(config)

  def circadian_config(config) do
    case CircadianConfig.load(config) do
      {:ok, circadian_config} -> circadian_config
      {:error, _errors} -> %CircadianConfig{}
    end
  end

  def persisted_config(%__MODULE__{type: type, config: %Config{} = config}),
    do: Config.persisted_config(config, type)

  def persisted_config(%Config{} = config), do: Config.persisted_config(config, :manual)

  def persisted_config(%__MODULE__{config: config}) when is_map(config),
    do: stringify_keys(config)

  def persisted_config(config) when is_map(config), do: stringify_keys(config)
  def persisted_config(_config), do: %{}

  defp stringify_keys(config) do
    Enum.into(config, %{}, fn {key, value} ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      {normalized_key, value}
    end)
  end

  defp cast_type_config(changeset, _attrs) do
    case get_field(changeset, :type) do
      :manual ->
        cast_embed(changeset, :config, with: &Config.manual_changeset/2)

      :circadian ->
        cast_embed(changeset, :config, with: &Config.circadian_changeset/2)

      _ ->
        changeset
    end
  end
end
