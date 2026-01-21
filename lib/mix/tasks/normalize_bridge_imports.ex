defmodule Mix.Tasks.NormalizeBridgeImports do
  use Mix.Task

  @shortdoc "Normalize raw bridge import JSON to normalized JSON files"

  @moduledoc """
  Normalize raw bridge import files produced by mix export_bridge_imports.

  Usage:

      mix normalize_bridge_imports
      mix normalize_bridge_imports path/to/raw.json
  """

  alias Hueworks.Import.Normalize
  alias Hueworks.Schemas.Bridge

  @impl true
  def run(args) do
    Mix.Task.run("app.config")

    files =
      case args do
        [] -> default_files()
        paths -> paths
      end

    Enum.each(files, &normalize_file/1)
  end

  defp default_files do
    Path.wildcard(Path.join("exports", "*_raw_*.json"))
  end

  defp normalize_file(path) do
    payload = path |> File.read!() |> Jason.decode!()

    bridge_data = payload["bridge"] || %{}
    raw = payload["raw"] || %{}
    fetched_at = payload["fetched_at"]

    bridge = %Bridge{
      id: bridge_data["id"],
      type: to_bridge_type(bridge_data["type"]),
      name: bridge_data["name"],
      host: bridge_data["host"]
    }

    normalized = Normalize.normalize(bridge, raw)

    output = %{
      bridge: bridge_data,
      fetched_at: fetched_at,
      normalized_at: normalized.normalized_at,
      normalized: normalized
    }

    filename = normalized_filename(path, fetched_at)
    out_path = Path.join("exports", filename)
    File.write!(out_path, Jason.encode!(output, pretty: true))
    Mix.shell().info("Wrote #{out_path}")
  rescue
    error -> Mix.shell().error("Failed to normalize #{path}: #{Exception.message(error)}")
  end

  defp to_bridge_type(nil), do: nil
  defp to_bridge_type(type) when is_atom(type), do: type
  defp to_bridge_type(type) when is_binary(type), do: String.to_atom(type)

  defp normalized_filename(path, fetched_at) do
    base = Path.basename(path)

    timestamp =
      case fetched_at do
        value when is_binary(value) -> timestamp_from_iso(value)
        _ -> timestamp_now()
      end

    base
    |> String.replace("_raw_", "_normalized_")
    |> String.replace(~r/_\d{8}T\d{6}\.json$/, "_#{timestamp}.json")
  end

  defp timestamp_from_iso(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        dt
        |> DateTime.truncate(:second)
        |> Calendar.strftime("%Y%m%dT%H%M%S")

      _ ->
        timestamp_now()
    end
  end

  defp timestamp_now do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  end
end
