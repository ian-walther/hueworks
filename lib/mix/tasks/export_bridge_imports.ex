defmodule Mix.Tasks.ExportBridgeImports do
  use Mix.Task

  @shortdoc "Fetch raw bridge config and dump to JSON files"

  @moduledoc """
  Fetch raw configuration for each bridge and write JSON files to exports/.

  Usage:

      mix export_bridge_imports
  """

  alias Hueworks.Import.Pipeline
  alias Hueworks.Repo
  alias Hueworks.Schemas.Bridge

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    timestamp = timestamp()
    bridges = Repo.all(Bridge)

    Enum.each(bridges, fn bridge ->
      case Pipeline.fetch_raw(bridge) do
        {:ok, raw_blob} ->
          payload = %{
            bridge: %{
              id: bridge.id,
              type: bridge.type,
              name: bridge.name,
              host: bridge.host
            },
            fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
            raw: raw_blob
          }

          filename = export_filename(bridge, timestamp)
          path = Path.join("exports", filename)
          File.mkdir_p!("exports")
          File.write!(path, Jason.encode!(payload, pretty: true))
          Mix.shell().info("Wrote #{path}")

        {:error, reason} ->
          Mix.shell().error("Failed to export #{bridge.name}: #{inspect(reason)}")
      end
    end)
  end

  defp export_filename(bridge, timestamp) do
    type = bridge.type |> to_string()
    host = bridge.host |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
    "#{type}_raw_#{host}_#{timestamp}.json"
  end

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  end
end
