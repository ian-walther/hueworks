defmodule Mix.Tasks.Fetch do
  use Mix.Task

  @shortdoc "Fetch Hue/Caseta/Home Assistant exports to JSON files"

  @moduledoc """
  Fetch device exports and write them to the exports/ directory.

  Usage:

      mix fetch
      mix fetch hue
      mix fetch caseta
      mix fetch ha
      mix fetch home_assistant
  """

  alias Hueworks.Exploration.ExportDevices

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case normalize_args(args) do
      :all ->
        ExportDevices.export_all()

      :hue ->
        write_one("hue_devices", ExportDevices.export_hue())

      :caseta ->
        write_one("lutron_devices", ExportDevices.export_lutron())

      :ha ->
        write_one("ha_entities", ExportDevices.export_home_assistant())

      :unknown ->
        Mix.raise("Unknown fetch target. Use: hue, caseta, ha, home_assistant")
    end
  end

  defp normalize_args([]), do: :all
  defp normalize_args(["hue"]), do: :hue
  defp normalize_args(["caseta"]), do: :caseta
  defp normalize_args(["ha"]), do: :ha
  defp normalize_args(["home_assistant"]), do: :ha
  defp normalize_args(_), do: :unknown

  defp write_one(prefix, data) do
    export_dir = "exports"
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0..14)
    File.mkdir_p!(export_dir)

    file_path = Path.join(export_dir, "#{prefix}_#{timestamp}.json")
    json = Jason.encode!(data, pretty: true)
    File.write!(file_path, json)
    Mix.shell().info("Saved to: #{file_path}")
  end
end
