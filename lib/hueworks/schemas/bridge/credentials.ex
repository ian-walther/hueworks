defmodule Hueworks.Schemas.Bridge.Credentials do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hueworks.Util

  @secret_fields [:api_key, :token, :password, :access_token, :refresh_token]
  @derive {Inspect, except: @secret_fields}
  @primary_key false
  embedded_schema do
    field(:api_key, :string, redact: true)
    field(:token, :string, redact: true)
    field(:cert_path, :string)
    field(:key_path, :string)
    field(:cacert_path, :string)
    field(:broker_port, :integer)
    field(:username, :string)
    field(:password, :string, redact: true)
    field(:base_topic, :string)
    field(:auth_type, :string)
    field(:access_token, :string, redact: true)
    field(:refresh_token, :string, redact: true)
    field(:expires_at, :integer)
    field(:client_id, :string)
    field(:auth_status, :string)
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
    :base_topic,
    :auth_type,
    :access_token,
    :refresh_token,
    :expires_at,
    :client_id,
    :auth_status
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
      {:error, changeset} -> {:error, Util.changeset_errors(changeset)}
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
    |> validate_inclusion(:auth_type, ["manual", "oauth"])
    |> validate_inclusion(:auth_status, ["ready", "reauthorization_required"])
    |> prune_unused_fields(type)
  end

  def changeset(credentials, _attrs, type), do: changeset(credentials, %{}, type)

  def dump(%__MODULE__{} = credentials) do
    %{}
    |> Util.put_unless_nil("api_key", credentials.api_key)
    |> Util.put_unless_nil("token", credentials.token)
    |> Util.put_unless_nil("cert_path", credentials.cert_path)
    |> Util.put_unless_nil("key_path", credentials.key_path)
    |> Util.put_unless_nil("cacert_path", credentials.cacert_path)
    |> Util.put_unless_nil("broker_port", credentials.broker_port)
    |> Util.put_unless_nil("username", credentials.username)
    |> Util.put_unless_nil("password", credentials.password)
    |> Util.put_unless_nil("base_topic", credentials.base_topic)
    |> Util.put_unless_nil("auth_type", credentials.auth_type)
    |> Util.put_unless_nil("access_token", credentials.access_token)
    |> Util.put_unless_nil("refresh_token", credentials.refresh_token)
    |> Util.put_unless_nil("expires_at", credentials.expires_at)
    |> Util.put_unless_nil("client_id", credentials.client_id)
    |> Util.put_unless_nil("auth_status", credentials.auth_status)
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
  defp normalize_value("expires_at", value), do: normalize_integer(value)
  defp normalize_value(_key, value) when is_binary(value), do: Util.blank_to_nil(value)
  defp normalize_value(_key, value), do: value

  defp normalize_port(value) do
    case Util.parse_optional_integer(value) do
      port when is_integer(port) -> port
      _ -> value
    end
  end

  defp normalize_integer(value) do
    case Util.parse_optional_integer(value) do
      integer when is_integer(integer) -> integer
      _ -> value
    end
  end

  defp prune_unused_fields(changeset, :hue) do
    changeset
    |> keep_fields([:api_key])
  end

  defp prune_unused_fields(changeset, :ha) do
    changeset
    |> keep_fields([
      :token,
      :auth_type,
      :access_token,
      :refresh_token,
      :expires_at,
      :client_id,
      :auth_status
    ])
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

  defp stringify_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end
end
