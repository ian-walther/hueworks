defmodule Hueworks.BridgeSeeds do
  @moduledoc """
  Loads bridge seed definitions from a JSON file and upserts them into the database.
  """

  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  @default_path "secrets.json"

  def default_path do
    System.get_env("BRIDGE_SECRETS_PATH") || @default_path
  end

  def load_from_file(path \\ default_path()) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, bridges} <- normalize_root(decoded) do
      {:ok, bridges}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, path, Exception.message(error)}}

      {:error, :enoent} ->
        {:error, {:missing_file, path}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def seed_from_file(path \\ default_path()) when is_binary(path) do
    with {:ok, bridges} <- load_from_file(path) do
      Repo.transaction(fn ->
        Enum.reduce_while(bridges, 0, fn attrs, count ->
          case upsert_bridge(attrs) do
            {:ok, _bridge} ->
              {:cont, count + 1}

            {:error, changeset} ->
              Repo.rollback({:invalid_bridge, attrs, changeset})
          end
        end)
      end)
      |> case do
        {:ok, count} -> {:ok, count}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp normalize_root(%{"bridges" => bridges}) when is_list(bridges) do
    bridges
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      case normalize_bridge(entry) do
        {:ok, bridge} -> {:cont, {:ok, [bridge | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_bridge_entry, index, reason}}}
      end
    end)
    |> case do
      {:ok, bridges} -> {:ok, Enum.reverse(bridges)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_root(%{}), do: {:error, {:invalid_shape, "expected top-level \"bridges\" list"}}
  defp normalize_root(_), do: {:error, {:invalid_shape, "expected JSON object"}}

  defp normalize_bridge(%{} = attrs) do
    with {:ok, type} <- normalize_type(Map.get(attrs, "type")),
         {:ok, name} <- normalize_string_field(attrs, "name"),
         {:ok, host} <- normalize_string_field(attrs, "host"),
         {:ok, credentials} <- normalize_credentials(Map.get(attrs, "credentials")) do
      {:ok,
       %{
         type: type,
         name: name,
         host: host,
         credentials: credentials,
         enabled: normalize_boolean(Map.get(attrs, "enabled"), true),
         import_complete: normalize_boolean(Map.get(attrs, "import_complete"), false)
       }}
    end
  end

  defp normalize_bridge(_), do: {:error, "expected bridge entry object"}

  defp normalize_type("hue"), do: {:ok, :hue}
  defp normalize_type("caseta"), do: {:ok, :caseta}
  defp normalize_type("ha"), do: {:ok, :ha}
  defp normalize_type("z2m"), do: {:ok, :z2m}

  defp normalize_type(value), do: {:error, "unsupported bridge type #{inspect(value)}"}

  defp normalize_string_field(attrs, key) do
    value =
      attrs
      |> Map.get(key)
      |> case do
        value when is_binary(value) -> String.trim(value)
        other -> other
      end

    if is_binary(value) and value != "" do
      {:ok, value}
    else
      {:error, "missing #{key}"}
    end
  end

  defp normalize_credentials(credentials) when is_map(credentials) and map_size(credentials) > 0 do
    {:ok, stringify_keys(credentials)}
  end

  defp normalize_credentials(_), do: {:error, "credentials must be a non-empty object"}

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean(nil, default), do: default
  defp normalize_boolean(_value, default), do: default

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {
        to_string(key),
        if(is_map(value), do: stringify_keys(value), else: value)
      }
    end)
  end

  defp upsert_bridge(attrs) do
    case Repo.get_by(Bridge, type: attrs.type, host: attrs.host) do
      nil ->
        %Bridge{}
        |> Bridge.changeset(attrs)
        |> Repo.insert()

      bridge ->
        bridge
        |> Bridge.changeset(attrs)
        |> Repo.update()
    end
  end
end
