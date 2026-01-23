defmodule Mix.Tasks.MaterializeBridgeImports do
  use Mix.Task

  @shortdoc "Materialize normalized bridge JSON into the database"

  @moduledoc """
  Materialize normalized bridge files produced by mix normalize_bridge_imports.

  Usage:

      mix materialize_bridge_imports
      mix materialize_bridge_imports path/to/normalized.json
  """

  alias Hueworks.Import.Materialize
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    files =
      case args do
        [] -> default_files()
        paths -> paths
      end

    Enum.each(files, &materialize_file/1)
  end

  defp default_files do
    Path.wildcard(Path.join("exports", "*_normalized_*.json"))
  end

  defp materialize_file(path) do
    payload = path |> File.read!() |> Jason.decode!()
    bridge_data = payload["bridge"] || %{}
    normalized = payload["normalized"] || %{}

    with {:ok, bridge} <- find_bridge(bridge_data) do
      Materialize.materialize(bridge, normalized)
      Mix.shell().info("Materialized #{path}")
    end
  rescue
    error -> Mix.shell().error("Failed to materialize #{path}: #{Exception.message(error)}")
  end

  defp find_bridge(%{"host" => host, "type" => type}) do
    bridge_type = to_bridge_type(type)

    case Repo.get_by(Bridge, host: host, type: bridge_type) do
      nil -> {:error, "No bridge found for #{host} (#{type})"}
      bridge -> {:ok, bridge}
    end
  end

  defp find_bridge(_bridge_data) do
    {:error, "Missing bridge host/type in normalized file"}
  end

  defp to_bridge_type(nil), do: nil
  defp to_bridge_type(type) when is_atom(type), do: type
  defp to_bridge_type(type) when is_binary(type), do: String.to_atom(type)
end
