defmodule Hueworks.Schemas.Bridge.Credentials do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Util

  @primary_key false
  embedded_schema do
    field(:api_key, :string)
    field(:token, :string)
    field(:cert_path, :string)
    field(:key_path, :string)
    field(:cacert_path, :string)
    field(:broker_port, :integer)
    field(:username, :string)
    field(:password, :string)
    field(:base_topic, :string)
  end

  @fields [
    :api_key,
    :token,
    :cert_path,
    :key_path,
    :cacert_path,
    :broker_port,
    :username,
    :password,
    :base_topic
  ]

  def load(type, %__MODULE__{} = credentials) when type in [:hue, :ha, :caseta, :z2m],
    do: credentials

  def load(type, attrs) when type in [:hue, :ha, :caseta, :z2m] and is_map(attrs) do
    attrs
    |> changeset(type)
    |> apply_action(:validate)
    |> case do
      {:ok, credentials} -> credentials
      {:error, _changeset} -> %__MODULE__{}
    end
  end

  def load(_type, _attrs), do: %__MODULE__{}

  def normalize(type, attrs) when type in [:hue, :ha, :caseta, :z2m] and is_map(attrs) do
    attrs
    |> changeset(type)
    |> apply_action(:validate)
    |> case do
      {:ok, credentials} -> {:ok, dump(credentials)}
      {:error, changeset} -> {:error, changeset_errors(changeset)}
    end
  end

  def normalize(_type, attrs) when is_map(attrs), do: {:ok, stringify_map(attrs)}
  def normalize(_type, _attrs), do: {:error, [{"credentials", "must be a map"}]}

  def changeset(attrs, type), do: changeset(%__MODULE__{}, attrs, type)

  def changeset(credentials, attrs, type) when is_map(attrs) do
    attrs = normalize_input(attrs)

    credentials
    |> cast(attrs, @fields)
    |> validate_number(:broker_port, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535)
    |> prune_unused_fields(type)
  end

  def changeset(credentials, _attrs, type), do: changeset(credentials, %{}, type)

  def dump(%__MODULE__{} = credentials) do
    %{}
    |> maybe_put("api_key", credentials.api_key)
    |> maybe_put("token", credentials.token)
    |> maybe_put("cert_path", credentials.cert_path)
    |> maybe_put("key_path", credentials.key_path)
    |> maybe_put("cacert_path", credentials.cacert_path)
    |> maybe_put("broker_port", credentials.broker_port)
    |> maybe_put("username", credentials.username)
    |> maybe_put("password", credentials.password)
    |> maybe_put("base_topic", credentials.base_topic)
  end

  defp normalize_input(attrs) do
    Enum.into(attrs, %{}, fn {key, value} ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      {normalized_key, normalize_value(normalized_key, value)}
    end)
  end

  defp normalize_value("broker_port", value), do: normalize_port(value)
  defp normalize_value(_key, value), do: normalize_optional_string(value)

  defp normalize_port(value) do
    case Util.parse_optional_integer(value) do
      port when is_integer(port) -> port
      _ -> value
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional_string(value), do: value

  defp prune_unused_fields(changeset, :hue) do
    changeset
    |> keep_fields([:api_key])
  end

  defp prune_unused_fields(changeset, :ha) do
    changeset
    |> keep_fields([:token])
  end

  defp prune_unused_fields(changeset, :caseta) do
    changeset
    |> keep_fields([:cert_path, :key_path, :cacert_path])
  end

  defp prune_unused_fields(changeset, :z2m) do
    changeset
    |> keep_fields([:broker_port, :username, :password, :base_topic])
  end

  defp prune_unused_fields(changeset, _type), do: changeset

  defp keep_fields(changeset, allowed_fields) do
    drop_fields = @fields -- allowed_fields

    Enum.reduce(drop_fields, changeset, fn field, acc ->
      put_change(acc, field, nil)
    end)
  end

  defp changeset_errors(changeset) do
    traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(List.wrap(messages), fn message -> {Atom.to_string(field), message} end)
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
