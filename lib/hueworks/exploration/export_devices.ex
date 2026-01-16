defmodule Hueworks.Exploration.ExportDevices do
  @moduledoc """
  Export device information from Hue, Lutron, and Home Assistant for deduplication analysis.
  """

  @export_dir "exports"

  @doc """
  Export all device information from Hue, Lutron, and Home Assistant.

  Saves timestamped JSON files to #{@export_dir}/

  ## Example

      ExportDevices.export_all()
  """
  def export_all do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0..14)

    File.mkdir_p!(@export_dir)

    IO.puts("\n=== Exporting Hue Devices ===")
    hue_data = export_hue()
    hue_file = Path.join(@export_dir, "hue_devices_#{timestamp}.json")
    write_json(hue_file, hue_data)
    IO.puts("Saved to: #{hue_file}")

    IO.puts("\n=== Exporting Lutron Devices ===")
    lutron_data = export_lutron()
    lutron_file = Path.join(@export_dir, "lutron_devices_#{timestamp}.json")
    write_json(lutron_file, lutron_data)
    IO.puts("Saved to: #{lutron_file}")

    IO.puts("\n=== Exporting Home Assistant Entities ===")
    ha_data = export_home_assistant()
    ha_file = Path.join(@export_dir, "ha_entities_#{timestamp}.json")
    write_json(ha_file, ha_data)
    IO.puts("Saved to: #{ha_file}")

    IO.puts("\n=== Export Complete ===")
    IO.puts("Files saved to: #{@export_dir}")

    %{
      hue_file: hue_file,
      lutron_file: lutron_file,
      ha_file: ha_file,
      timestamp: timestamp
    }
  end

  @doc """
  Export Hue device information.
  """
  def export_hue do
    Hueworks.Fetch.Hue.fetch()
  end

  @doc """
  Export Lutron device information.
  """
  def export_lutron do
    Hueworks.Fetch.Caseta.fetch()
  end

  @doc """
  Export Home Assistant entity information.
  """
  def export_home_assistant do
    Hueworks.Fetch.HomeAssistant.fetch()
  end

  defp write_json(file_path, data) do
    json = Jason.encode!(data, pretty: true)
    File.write!(file_path, json)
  end
end
