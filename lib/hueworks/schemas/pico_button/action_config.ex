defmodule Hueworks.Schemas.PicoButton.ActionConfig do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Picos.Targets
  alias Hueworks.Util

  @primary_key false
  embedded_schema do
    field(:target_kind, Ecto.Enum, values: [:scene, :all_groups, :control_group])
    field(:scene_id, :integer)
    field(:control_group_id, :string)
    field(:light_ids, {:array, :integer}, default: [])
    field(:room_id, :integer)
  end

  @fields [:target_kind, :scene_id, :control_group_id, :light_ids, :room_id]

  def load(%__MODULE__{} = config), do: config

  def load(attrs) when is_map(attrs) do
    attrs
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, config} -> config
      {:error, _changeset} -> %__MODULE__{}
    end
  end

  def load(_attrs), do: %__MODULE__{}

  def normalize(attrs) when is_map(attrs) do
    attrs
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, config} -> {:ok, dump(config)}
      {:error, changeset} -> {:error, changeset_errors(changeset)}
    end
  end

  def normalize(_attrs), do: {:error, [{"action_config", "must be a map"}]}

  def target_id(%__MODULE__{target_kind: :scene, scene_id: scene_id}), do: scene_id

  def target_id(%__MODULE__{target_kind: :control_group, control_group_id: group_id}),
    do: group_id

  def target_id(_config), do: nil

  def changeset(attrs), do: changeset(%__MODULE__{}, attrs)

  def changeset(config, attrs) when is_map(attrs) do
    attrs = normalize_input(attrs)

    config
    |> cast(attrs, @fields)
    |> validate_target_fields()
  end

  def changeset(config, _attrs), do: changeset(config, %{})

  def dump(%__MODULE__{} = config) do
    %{}
    |> maybe_put("target_kind", dump_target_kind(config.target_kind))
    |> maybe_put("target_id", target_id(config))
    |> maybe_put_if("light_ids", config.light_ids, fn ids -> ids != [] end)
    |> maybe_put("room_id", config.room_id)
  end

  defp normalize_input(attrs) do
    target_kind =
      normalized_target_kind(Map.get(attrs, :target_kind) || Map.get(attrs, "target_kind"))

    target_id = Map.get(attrs, :target_id) || Map.get(attrs, "target_id")

    %{}
    |> maybe_put("target_kind", target_kind)
    |> maybe_put_target_id(target_kind, target_id)
    |> maybe_put_if(
      "light_ids",
      Targets.normalize_integer_ids(
        Map.get(attrs, :light_ids) || Map.get(attrs, "light_ids") || []
      ),
      fn ids -> ids != [] end
    )
    |> maybe_put(
      "room_id",
      Util.parse_optional_integer(Map.get(attrs, :room_id) || Map.get(attrs, "room_id"))
    )
  end

  defp normalized_target_kind(kind) when kind in [:scene, :all_groups, :control_group], do: kind
  defp normalized_target_kind("scene"), do: :scene
  defp normalized_target_kind("all_groups"), do: :all_groups
  defp normalized_target_kind("control_group"), do: :control_group
  defp normalized_target_kind(_kind), do: nil

  defp maybe_put_target_id(attrs, :scene, target_id) do
    maybe_put(attrs, "scene_id", Util.parse_optional_integer(target_id))
  end

  defp maybe_put_target_id(attrs, :control_group, target_id) do
    target_id
    |> normalize_control_group_id()
    |> then(&maybe_put(attrs, "control_group_id", &1))
  end

  defp maybe_put_target_id(attrs, _target_kind, _target_id), do: attrs

  defp normalize_control_group_id(target_id) when is_binary(target_id) do
    case String.trim(target_id) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_control_group_id(target_id) when is_atom(target_id),
    do: Atom.to_string(target_id)

  defp normalize_control_group_id(_target_id), do: nil

  defp validate_target_fields(changeset) do
    case get_field(changeset, :target_kind) do
      :scene ->
        changeset
        |> validate_required([:scene_id])
        |> put_change(:control_group_id, nil)

      :control_group ->
        changeset
        |> validate_required([:control_group_id])
        |> put_change(:scene_id, nil)

      :all_groups ->
        changeset
        |> put_change(:scene_id, nil)
        |> put_change(:control_group_id, nil)

      nil ->
        changeset
    end
  end

  defp dump_target_kind(nil), do: nil
  defp dump_target_kind(kind), do: Atom.to_string(kind)

  defp changeset_errors(changeset) do
    traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", format_opt_value(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(List.wrap(messages), fn message -> {error_field(field), message} end)
    end)
  end

  defp error_field(:scene_id), do: "target_id"
  defp error_field(:control_group_id), do: "target_id"
  defp error_field(field), do: Atom.to_string(field)

  defp format_opt_value(value) when is_binary(value), do: value
  defp format_opt_value(value), do: inspect(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_if(map, key, value, predicate) when is_function(predicate, 1) do
    if predicate.(value), do: Map.put(map, key, value), else: map
  end
end
